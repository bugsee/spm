//
//  CorpseReader+Run.swift
//  BugseeCrashExtension
//
//  Copyright © 2026 Bugsee. All rights reserved.
//

#if os(iOS) && canImport(CrashReportExtension)

import Darwin
import Foundation
import MachO

/// What the corpse says about the run that died, beyond the kernel's crash info.
extension CorpseReader {
    /// The dead task's `TASK_CATEGORY_POLICY` role, as RunningBoard last set it; nil when the
    /// kernel does not answer. Seen on iPadOS 27.2: 1 (foreground) for a jetsam and a watchdog
    /// in the foreground, 8 (darwin-bg) for a jetsam and 6 (non-UI) for a watchdog in the
    /// background.
    func taskRole() -> Int32? {
        var policy = task_category_policy_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_category_policy_data_t>.size / MemoryLayout<integer_t>.size)
        var isDefault: boolean_t = 0
        let result = withUnsafeMutablePointer(to: &policy) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_policy_get(port, task_policy_flavor_t(TASK_CATEGORY_POLICY), $0, &count,
                                &isDefault)
            }
        }
        return result == KERN_SUCCESS ? policy.role.rawValue : nil
    }

    /// The SDK's run record (`BGSExitRunRecord` in BGSDetectionProviderExit.m): the dead
    /// process's run id and how far Bugsee got (0 none, 1 launching, 2 tracked).
    struct RunRecord {
        let state: UInt32
        let runId: UUID
    }

    /// `char magic[8]`, `uint32 state`, `uint32 reserved`, `uuid_t runId`.
    private static let runRecordMagic = Array("BGSRUN1\0".utf8)
    private static let runRecordSize = 32

    /// The run record read out of the dead process's memory, from the first of `imageBases`
    /// with a `__DATA,__bgs_run` section that holds one; nil when none does.
    func runRecord(imageBases: [UInt64]) -> RunRecord? {
        for base in imageBases {
            guard let address = sectionAddress(imageBase: base, segment: "__DATA",
                                               section: "__bgs_run",
                                               minimumSize: UInt64(Self.runRecordSize))
            else { continue }
            var bytes = [UInt8](repeating: 0, count: Self.runRecordSize)
            guard bytes.withUnsafeMutableBytes({ readBytes(address, into: $0) }),
                  bytes.prefix(8).elementsEqual(Self.runRecordMagic) else { continue }
            return bytes.withUnsafeBytes {
                RunRecord(state: $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self),
                          runId: UUID(uuid: $0.loadUnaligned(fromByteOffset: 16, as: uuid_t.self)))
            }
        }
        return nil
    }

    /// The slid address of `segment,section` in the image at `base`; nil when the image has no
    /// such section, or a smaller one.
    private func sectionAddress(imageBase base: UInt64, segment: String, section: String,
                                minimumSize: UInt64) -> UInt64? {
        guard let (header, commands) = loadCommands(imageBase: base) else { return nil }
        return commands.withUnsafeBytes { buffer -> UInt64? in
            var textAddress: UInt64?
            var found: UInt64?
            var offset = 0
            for _ in 0..<Int(header.ncmds) {
                guard offset + 8 <= buffer.count else { break }
                let command = buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
                let size = Int(buffer.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))
                guard size > 0, offset + size <= buffer.count else { break }
                // segment_command_64: segname at 8, vmaddr at 24, nsects at 64; 72 bytes.
                if command == 0x19, size >= 72 {  // LC_SEGMENT_64
                    let name = buffer[(offset + 8)..<(offset + 24)].prefix { $0 != 0 }
                    if name.elementsEqual("__TEXT".utf8) {
                        textAddress = buffer.loadUnaligned(fromByteOffset: offset + 24, as: UInt64.self)
                    } else if name.elementsEqual(segment.utf8) {
                        found = Self.sectionAddress(in: buffer, segmentAt: offset, size: size,
                                                    named: section, minimumSize: minimumSize)
                    }
                }
                offset += size
            }
            guard let textAddress, let found else { return nil }
            return found &+ (base &- textAddress)
        }
    }

    /// The unslid address of section `name` among the `section_64` headers (80 bytes each:
    /// sectname at 0, addr at 32, size at 40) that follow the segment command at `offset`.
    private static func sectionAddress(in buffer: UnsafeRawBufferPointer, segmentAt offset: Int,
                                       size: Int, named name: String,
                                       minimumSize: UInt64) -> UInt64? {
        let sections = Int(buffer.loadUnaligned(fromByteOffset: offset + 64, as: UInt32.self))
        for index in 0..<sections {
            let header = offset + 72 + index * 80
            guard header + 80 <= offset + size else { return nil }
            let sectionName = buffer[header..<(header + 16)].prefix { $0 != 0 }
            if sectionName.elementsEqual(name.utf8) {
                let sectionSize = buffer.loadUnaligned(fromByteOffset: header + 40, as: UInt64.self)
                guard sectionSize >= minimumSize else { return nil }
                return buffer.loadUnaligned(fromByteOffset: header + 32, as: UInt64.self)
            }
        }
        return nil
    }
}

#endif
