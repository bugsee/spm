//
//  CorpseReader.swift
//  BugseeCrashExtension
//
//  Copyright © 2026 Bugsee. All rights reserved.
//

#if os(iOS) && canImport(CrashReportExtension)

import Darwin
import Foundation
import MachO

/// Read-only access to the corpse the system hands the extension: threads, registers, the
/// frame-pointer chain, Mach-O headers, and the kernel's kcdata crash info.
///
/// Nothing here suspends a thread: on a corpse `thread_suspend` returns `KERN_TERMINATED`,
/// and `thread_get_state` works without it.
///
/// Mechanics only: no JSON, no policy. `CorpseReport` decides what goes into the document.
nonisolated struct CorpseReader {
    let port: mach_port_t

    /// iOS user space fits in 36 bits; anything above is a pointer-auth signature.
    static let addressMask: UInt64 = 0x0000_000F_FFFF_FFFF

    struct Thread {
        let number: Int
        let identifier: UInt64?
        /// The program counter first, then return addresses up the frame-pointer chain.
        let frames: [UInt64]
    }

    /// Why the kernel ended the process. Namespaces seen on device: 1 jetsam (code 7, the
    /// per-process limit), 2 signal (code = signal number), 3 code signing (code 2, invalid
    /// page), 10 FrontBoard (`0x8BADF00D`, the launch watchdog). Flag `0x2` marks a reason the
    /// kernel wants a crash report for — what gets a SIGKILL a corpse at all. Per the XNU
    /// source (not seen on device), a fatal guard (23) or port-space (30) kill stores the raw
    /// Mach exception code, with its type in bits 63:61, so `code` uses all 64 bits.
    struct ExitReason {
        let namespace: UInt32
        let code: UInt64
        let flags: UInt64
    }

    struct CrashInfo {
        /// `TASK_CRASHINFO_PID`: the dead process.
        var pid: Int32?
        /// `TASK_CRASHINFO_CRASHED_THREADID`: a kernel thread id, not an index; matched to a
        /// corpse thread through `THREAD_IDENTIFIER_INFO`.
        var crashedThreadID: UInt64?
        /// `EXIT_REASON_SNAPSHOT`, absent for some signal deaths (see `CorpseReport`).
        var exitReason: ExitReason?
        /// `TASK_CRASHINFO_EXCEPTION_CODES`. For a signal death the first code carries the
        /// signal number in bits 24–31 even when no exit-reason snapshot was recorded.
        var exceptionCodes: [UInt64] = []
        /// `TASK_CRASHINFO_PROC_STARTTIME`, microseconds since 1970.
        var startTimeMicroseconds: Int64?
        /// `EXIT_REASON_USER_DESC`: the text the killer attached to the exit reason, if any.
        var reasonDescription: String?
    }

    /// `EXIT_REASON_USER_DESC` is a C string; longer text is cut here.
    static let reasonDescriptionLimit = 1024

    // MARK: - Threads

    /// Every thread of the corpse, in `task_threads` order (that index is the `number` in
    /// crash.json). Once `deadline` has passed, a thread keeps only its pc, so a slow walk
    /// cannot run into the system's kill of the extension. `functionStart` maps an address to
    /// the start of the function containing it, nil when unknown (see `walk`).
    func threads(limit: Int, frameLimit: Int, deadline: UInt64,
                 functionStart: (UInt64) -> UInt64?) -> [Thread] {
        var list: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(port, &list, &count) == KERN_SUCCESS, let list else { return [] }
        defer {
            for index in 0..<Int(count) {
                mach_port_deallocate(mach_task_self_, list[index])
            }
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: list)),
                          vm_size_t(Int(count) * MemoryLayout<thread_act_t>.stride))
        }

        var result: [Thread] = []
        for index in 0..<min(Int(count), limit) {
            let thread = list[index]
            guard let registers = registers(of: thread) else { continue }
            let frames = DispatchTime.now().uptimeNanoseconds < deadline
                ? walk(registers, limit: frameLimit, functionStart: functionStart)
                : [registers.pc & Self.addressMask]
            result.append(Thread(number: index, identifier: identifier(of: thread), frames: frames))
        }
        return result
    }

    private func identifier(of thread: thread_act_t) -> UInt64? {
        var info = thread_identifier_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<thread_identifier_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(thread, thread_flavor_t(THREAD_IDENTIFIER_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info.thread_id : nil
    }

    private struct Registers {
        let pc: UInt64
        let lr: UInt64
        let fp: UInt64
    }

    private func registers(of thread: thread_act_t) -> Registers? {
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size)
        let kr = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                thread_get_state(thread, ARM_THREAD_STATE64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        // On an arm64e build the opaque fields may carry a pointer-auth signature;
        // `addressMask` strips it wherever they are used. Untested: no arm64e host or appex
        // has run.
#if _ptrauth(_arm64e)
        return Registers(pc: UInt64(UInt(bitPattern: state.__opaque_pc)),
                         lr: UInt64(UInt(bitPattern: state.__opaque_lr)),
                         fp: UInt64(UInt(bitPattern: state.__opaque_fp)))
#else
        return Registers(pc: state.__pc, lr: state.__lr, fp: state.__fp)
#endif
    }

    /// Each frame record holds the caller's fp at `fp` and the return address at `fp + 8`.
    /// Frame pointers only: code built without them ends the chain early. No DWARF or compact
    /// unwind in v1.
    ///
    /// `lr` names the caller only while the function at pc has no frame record of its own: a
    /// leaf, a prologue, or code past the epilogue. In between, after any call, `lr` is that
    /// call's return address inside pc's own function, and the caller is at `fp + 8`. So `lr`
    /// is taken unless it equals `fp + 8` or its call site is in pc's function; when the
    /// function bounds are unknown, it is taken. A function that calls itself and faults in
    /// its prologue (a recursive stack overflow) loses its innermost caller frame this way.
    private func walk(_ registers: Registers, limit: Int,
                      functionStart: (UInt64) -> UInt64?) -> [UInt64] {
        let pc = registers.pc & Self.addressMask
        var frames = [pc]
        var fp = registers.fp & Self.addressMask
        let lr = registers.lr & Self.addressMask
        let savedReturn = fp == 0 ? nil : readUInt64(fp + 8).map { $0 & Self.addressMask }
        // The call that set lr is the instruction before it.
        if lr != 0, lr != savedReturn, !Self.inSameFunction(pc, lr &- 4, functionStart) {
            frames.append(lr)
        }
        while fp != 0, frames.count < limit {
            guard let next = readUInt64(fp), let ret = readUInt64(fp + 8), ret != 0 else { break }
            frames.append(ret & Self.addressMask)
            let nextFP = next & Self.addressMask
            if nextFP <= fp { break }
            fp = nextFP
        }
        return frames
    }

    /// False whenever either address has no known function.
    private static func inSameFunction(_ first: UInt64, _ second: UInt64,
                                       _ functionStart: (UInt64) -> UInt64?) -> Bool {
        guard let start = functionStart(first) else { return false }
        return functionStart(second) == start
    }

    // MARK: - Mach-O

    /// What the walk and the image table need from an image's load commands.
    private struct Layout {
        var text: (address: UInt64, size: UInt64)?
        var linkedit: (address: UInt64, fileOffset: UInt64)?
        var functionStarts: (offset: UInt32, size: UInt32)?
    }

    /// About 3× the largest table measured (clang: 276,678 functions, 369,712 bytes). A larger
    /// one reads as no table, which keeps `lr` as before.
    private static let functionStartsLimit: UInt32 = 1 << 20

    /// A `__TEXT` larger than this is a corrupt header; leaving it out keeps `base + size`
    /// from overflowing wherever the size is used.
    private static let textSizeLimit: UInt64 = 1 << 32

    /// The `__TEXT` vmsize of the image at `base` — the image size PLCrashReporter reports.
    /// `BinaryImageInfo.size` is not a Mach-O size for dyld shared-cache images.
    func textSegmentSize(imageBase base: UInt64) -> UInt64? {
        layout(imageBase: base)?.text?.size
    }

    /// The function start addresses of the image at `base`, ascending, from its
    /// `LC_FUNCTION_STARTS`: ULEB128 deltas, the first from the start of `__TEXT`, ended by a
    /// zero. Nil when the image has no such table or it does not decode to addresses inside
    /// `__TEXT`. Starts only: code after the last start (stubs) maps to the last function, so
    /// a fault inside a stub called from that function drops `lr` in `walk`.
    func functionStarts(imageBase base: UInt64) -> [UInt64]? {
        guard let layout = layout(imageBase: base), let text = layout.text,
              text.size > 0,
              let linkedit = layout.linkedit, let table = layout.functionStarts,
              table.size > 0, table.size <= Self.functionStartsLimit else { return nil }
        // A `__LINKEDIT` file offset lives at the segment's slid address plus its distance
        // from the segment's own file offset; the slide is how far `__TEXT` moved to `base`.
        let slide = base &- text.address
        let tableAddress = linkedit.address &+ slide &- linkedit.fileOffset &+ UInt64(table.offset)
        var bytes = [UInt8](repeating: 0, count: Int(table.size))
        let loaded = bytes.withUnsafeMutableBytes { readBytes(tableAddress, into: $0) }
        guard loaded else { return nil }

        var starts: [UInt64] = []
        var address = base
        var index = 0
        while index < bytes.count {
            var delta: UInt64 = 0
            var shift: UInt64 = 0
            var byte: UInt8
            repeat {
                guard index < bytes.count, shift < 64 else { return nil }
                byte = bytes[index]
                index += 1
                delta |= UInt64(byte & 0x7F) << shift
                shift += 7
            } while byte & 0x80 != 0
            if delta == 0 {
                break
            }
            guard delta < text.size, address + delta < base + text.size else { return nil }
            address += delta
            starts.append(address)
        }
        return starts.isEmpty ? nil : starts
    }

    /// The 64-bit Mach-O header of the image at `base` and its load commands; nil when the
    /// header is not one or the commands do not read.
    func loadCommands(imageBase base: UInt64) -> (header: mach_header_64, commands: [UInt8])? {
        var header = mach_header_64()
        guard read(base, into: &header), header.magic == 0xFEED_FACF else { return nil }
        let commandsSize = Int(header.sizeofcmds)
        guard commandsSize > 0, commandsSize < 1 << 20 else { return nil }
        var commands = [UInt8](repeating: 0, count: commandsSize)
        let loaded = commands.withUnsafeMutableBytes {
            readBytes(base + UInt64(MemoryLayout<mach_header_64>.size), into: $0)
        }
        return loaded ? (header, commands) : nil
    }

    private func layout(imageBase base: UInt64) -> Layout? {
        guard let (header, commands) = loadCommands(imageBase: base) else { return nil }
        let commandsSize = commands.count
        let segmentCommandSize = MemoryLayout<segment_command_64>.size
        return commands.withUnsafeBytes { buffer -> Layout in
            var layout = Layout()
            var offset = 0
            for _ in 0..<Int(header.ncmds) {
                guard offset + 8 <= commandsSize else { break }
                let command = buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
                let commandSize = Int(buffer.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))
                switch command {
                case 0x19 where offset + segmentCommandSize <= commandsSize:  // LC_SEGMENT_64
                    let name = buffer[(offset + 8)..<(offset + 24)].prefix { $0 != 0 }
                    // segment_command_64: vmaddr at 24, vmsize at 32, fileoff at 40.
                    let field = { (at: Int) in
                        buffer.loadUnaligned(fromByteOffset: offset + at, as: UInt64.self)
                    }
                    if name.elementsEqual("__TEXT".utf8), field(32) <= Self.textSizeLimit {
                        layout.text = (field(24), field(32))
                    } else if name.elementsEqual("__LINKEDIT".utf8) {
                        layout.linkedit = (field(24), field(40))
                    }
                case 0x26 where offset + 16 <= commandsSize:  // LC_FUNCTION_STARTS
                    layout.functionStarts = (
                        buffer.loadUnaligned(fromByteOffset: offset + 8, as: UInt32.self),
                        buffer.loadUnaligned(fromByteOffset: offset + 12, as: UInt32.self))
                default:
                    break
                }
                guard commandSize > 0 else { break }
                offset += commandSize
            }
            return layout
        }
    }

    // MARK: - kcdata

    /// Walks the kcdata blob `task_map_corpse_info_64` maps: 16-byte item headers
    /// (`uint32 type`, `uint32 size`, `uint64 flags`) followed by the payload.
    func crashInfo() -> CrashInfo {
        var info = CrashInfo()
        var address: mach_vm_address_t = 0
        var size: mach_vm_size_t = 0
        guard task_map_corpse_info_64(mach_task_self_, port, &address, &size) == KERN_SUCCESS,
              address != 0,
              let base = UnsafeRawPointer(bitPattern: UInt(address)) else {
            return info
        }
        defer { vm_deallocate(mach_task_self_, vm_address_t(address), vm_size_t(size)) }

        readItems(base, from: 0, to: Int(size), into: &info, isNested: false)
        return info
    }

    // MARK: - Memory

    func readUInt64(_ address: UInt64) -> UInt64? {
        var value: UInt64 = 0
        return read(address, into: &value) ? value : nil
    }

    private func read<T>(_ address: UInt64, into value: inout T) -> Bool {
        withUnsafeMutableBytes(of: &value) { readBytes(address, into: $0) }
    }

    func readBytes(_ address: UInt64, into buffer: UnsafeMutableRawBufferPointer) -> Bool {
        guard let destination = buffer.baseAddress else { return false }
        var copied: vm_size_t = 0
        let kr = vm_read_overwrite(port, vm_address_t(address), vm_size_t(buffer.count),
                                   vm_address_t(UInt(bitPattern: destination)), &copied)
        return kr == KERN_SUCCESS && Int(copied) == buffer.count
    }
}

// MARK: - kcdata items

extension CorpseReader {
    /// Reads the items in `[start, end)`. The exit reason's own kcdata (its description among
    /// it) is nested one level, as `KCDATA_TYPE_NESTED_KCDATA`, and read the same way.
    fileprivate func readItems(_ base: UnsafeRawPointer, from start: Int, to end: Int,
                               into info: inout CrashInfo, isNested: Bool) {
        var offset = start
        while offset + 16 <= end {
            let type = base.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            let itemSize = Int(base.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))
            let payload = offset + 16
            guard payload + itemSize <= end else { return }
            switch type {
            case 0x805 where itemSize >= 4:  // TASK_CRASHINFO_PID
                info.pid = base.loadUnaligned(fromByteOffset: payload, as: Int32.self)
            case 0x81A where itemSize >= 8:  // TASK_CRASHINFO_CRASHED_THREADID
                info.crashedThreadID = base.loadUnaligned(fromByteOffset: payload, as: UInt64.self)
            case 0x80E where itemSize >= 16:  // TASK_CRASHINFO_EXCEPTION_CODES
                info.exceptionCodes = [
                    base.loadUnaligned(fromByteOffset: payload, as: UInt64.self),
                    base.loadUnaligned(fromByteOffset: payload + 8, as: UInt64.self),
                ]
            // `struct exit_reason_snapshot`, packed: u32 namespace, u64 code, u64 flags.
            case 0x1001 where itemSize >= 20:  // EXIT_REASON_SNAPSHOT
                info.exitReason = ExitReason(
                    namespace: base.loadUnaligned(fromByteOffset: payload, as: UInt32.self),
                    code: base.loadUnaligned(fromByteOffset: payload + 4, as: UInt64.self),
                    flags: base.loadUnaligned(fromByteOffset: payload + 12, as: UInt64.self))
            case 0x38 where !isNested:  // KCDATA_TYPE_NESTED_KCDATA
                readItems(base, from: payload, to: payload + itemSize, into: &info, isNested: true)
            case 0xF191_58ED:  // KCDATA_TYPE_BUFFER_END
                return
            default:
                readValue(type: type, at: base + payload, size: itemSize, into: &info)
            }
            offset = payload + itemSize
        }
    }

    /// The items that need more than a load: a time and a string.
    private func readValue(type: UInt32, at payload: UnsafeRawPointer, size: Int,
                           into info: inout CrashInfo) {
        switch type {
        // `struct timeval64`: i64 seconds, i64 microseconds.
        case 0x80B where size >= 16:  // TASK_CRASHINFO_PROC_STARTTIME
            let seconds = payload.loadUnaligned(as: Int64.self)
            let micros = payload.loadUnaligned(fromByteOffset: 8, as: Int64.self)
            // Bounded so the arithmetic cannot trap on a damaged item.
            if (0..<(1 << 40)).contains(seconds), (0..<1_000_000).contains(micros) {
                info.startTimeMicroseconds = seconds * 1_000_000 + micros
            }
        case 0x1002 where size > 0:  // EXIT_REASON_USER_DESC
            let bytes = UnsafeRawBufferPointer(
                start: payload, count: min(size, Self.reasonDescriptionLimit))
            let text = bytes.prefix { $0 != 0 }
            if !text.isEmpty {
                info.reasonDescription = String(bytes: text, encoding: .utf8)
            }
        default:
            break
        }
    }
}

#endif
