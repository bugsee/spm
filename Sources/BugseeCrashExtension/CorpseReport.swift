//
//  CorpseReport.swift
//  BugseeCrashExtension
//
//  Copyright © 2026 Bugsee. All rights reserved.
//

#if os(iOS) && canImport(CrashReportExtension)

import CrashReportExtension
import Darwin
import Foundation
import os

/// Writes one document per death for the SDK to read on its next start:
/// `<App Group>/Library/Bugsee/corpses/corpse-<start>-<pid>.json`.
///
/// `threads` and `dyld` are already in the `crash.json` shapes the SDK writes from a
/// PLCrashReport (`_formatThreadsStructure`, `_formatBinaryImages`), so the SDK attaches
/// them to its `SIGBGS` document as they are. App-image frames stay `addr` only; the
/// worker symbolicates those from the dSYM and drops any device `trace` on them. System
/// frames get `trace` from `symbolicateAddresses`, the only name a beta OS ever gets.
@available(iOS 27.0, *)
nonisolated enum CorpseReport {
    private static let logger = Logger(subsystem: "com.bugsee.crashext", category: "report")
    private static let threadLimit = 128
    private static let frameLimit = 64
    private static let budgetNanoseconds: UInt64 = 1_000_000_000
    private static let logLimit: UInt64 = 64 * 1024
    /// Documents kept for an SDK that has not started since; past this the oldest goes.
    private static let documentLimit = 8
    /// The system makes no promise of one corpse at a time; the documents and the log are
    /// kept in order here. Recursive: `save` traces.
    private static let lock = NSRecursiveLock()

    static func write(for process: CrashedProcess) {
        let started = DispatchTime.now().uptimeNanoseconds
        trace("entered exception=\(process.reason.exception)")
        let reader = CorpseReader(port: process.corpsePort)

        let info = reader.crashInfo()
        let (exit, exitSource) = exitReason(info: info, reason: process.reason)
        let images = imageTable(process.binaryImages, reader: reader)
        // Function bounds for the walk's lr check, read per image on first use; an image
        // without a readable table maps to [] so it is read once.
        var startsByImage: [UInt64: [UInt64]] = [:]
        let threads = reader.threads(limit: threadLimit, frameLimit: frameLimit,
                                     deadline: started + budgetNanoseconds) { address in
            guard let image = image(containing: address, in: images) else { return nil }
            let starts = startsByImage[image.base] ?? {
                let read = reader.functionStarts(imageBase: image.base) ?? []
                startsByImage[image.base] = read
                return read
            }()
            return functionStart(of: address, in: starts)
        }
        let crashed = crashedThreadNumber(threads, info: info, images: images)
        let traces = systemTraces(threads, images: images, process: process)

        // What BGSCorpseReport reads: namespace/code choose the report type (1/7 jetsam,
        // 10/0x8BADF00D watchdog; any other namespace is logged and dropped today), run says
        // which run died and how far Bugsee got in it (the SDK's own record, read out of the
        // corpse), role says whether the app died in the foreground, reason says whether a
        // watchdog ran while the app was visible, and threads/dyld go onto crash.json
        // unchanged. pid and start name the document (the SDK reads the oldest first) and go
        // to the log; flags are stored, not used for a decision.
        var threadsJSON: [[String: Any]] = []
        for thread in threads {
            var frames: [[String: Any]] = []
            for address in thread.frames {
                var frame: [String: Any] = ["addr": Int(address)]
                frame["trace"] = traces[address]
                frames.append(frame)
            }
            threadsJSON.append(["number": thread.number,
                                "crashed": thread.number == crashed,
                                "frames": frames])
        }
        var document: [String: Any] = [
            "namespace": Int(exit.namespace),
            // Unconverted: a code can use bit 63 (see `ExitReason`), which `Int(_:)` traps on.
            "code": exit.code,
            "flags": exit.flags,
            "threads": threadsJSON,
            "dyld": images.map { $0.json },
        ]
        if let pid = info.pid {
            document["pid"] = Int(pid)
        }
        if let start = info.startTimeMicroseconds {
            document["start"] = start
        }
        if let description = info.reasonDescription {
            document["reason"] = description
        }
        let role = reader.taskRole()
        if let role {
            document["role"] = Int(role)
        }
        // Only app images can hold it: the SDK is linked into the app or embedded in it.
        let run = reader.runRecord(imageBases: images.filter(\.isUser).map(\.base))
        if let run {
            document["run"] = ["state": Int(run.state), "id": run.runId.uuidString]
        }
        let gatherMs = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        // Where the exit reason came from, and the raw inputs of the fallbacks.
        let reasonCodes: [String] = process.reason.codes.map { "0x" + String($0, radix: 16) }
        let exceptionCodes: [String] = info.exceptionCodes.map { "0x" + String($0, radix: 16) }
        trace("reason src=\(exitSource.rawValue) codes=\(reasonCodes) excCodes=\(exceptionCodes)")
        let tableless = startsByImage.values.filter(\.isEmpty).count
        trace("function starts: \(startsByImage.count) images read, \(tableless) without a table")
        let roleText = role.map(String.init) ?? "nil"
        let runText = run.map { "\($0.state)/\($0.runId.uuidString)" } ?? "nil"
        trace("gathered pid=\(info.pid.map(String.init) ?? "nil") ns=\(exit.namespace) "
              + "code=0x\(String(exit.code, radix: 16)) role=\(roleText) run=\(runText) "
              + "threads=\(threads.count) crashed=\(crashed) images=\(images.count) "
              + "traces=\(traces.count) in \(gatherMs) ms")
        save(document, name: documentName(startTime: info.startTimeMicroseconds, pid: info.pid))
    }

    // MARK: - Exit reason

    /// The snapshot when the kernel recorded one; otherwise the same pair from
    /// `CrashReason.codes[1]` (`namespace << 32 | code`); otherwise the signal number the
    /// exception codes carry, as a signal-namespace reason.
    ///
    /// On iPadOS 27.2 a death through PLCrashReporter's BSD handler (`abort()`,
    /// `raise(SIGSEGV)`: the handler re-raises the signal) left neither of the first two, only
    /// the signal in the exception codes. Hardware faults the Mach handler saw, jetsam,
    /// watchdog and code-signing kills all had the snapshot.
    private static func exitReason(
        info: CorpseReader.CrashInfo, reason: CrashReason
    ) -> (CorpseReader.ExitReason, ExitReasonSource) {
        if let snapshot = info.exitReason {
            return (snapshot, .snapshot)
        }
        if reason.codes.count > 1, reason.codes[1] != 0 {
            let packed = reason.codes[1]
            let pair = CorpseReader.ExitReason(
                namespace: UInt32(packed >> 32), code: packed & 0xFFFF_FFFF, flags: 0)
            return (pair, .codes)
        }
        if let first = info.exceptionCodes.first, (first >> 24) & 0xFF != 0 {
            return (.init(namespace: 2, code: (first >> 24) & 0xFF, flags: 0), .signal)
        }
        return (.init(namespace: 0, code: 0, flags: 0), .absent)
    }

    /// Which input `exitReason` used; diagnostic only, for the stage log.
    private enum ExitReasonSource: String {
        case snapshot
        case codes
        case signal
        case absent
    }

    // MARK: - Images

    private struct Image {
        let base: UInt64
        let size: UInt64
        let isUser: Bool
        let json: [String: Any]

        func contains(_ address: UInt64) -> Bool {
            address >= base && address < base + size
        }
    }

    private static func imageTable(_ infos: [BinaryImageInfo], reader: CorpseReader) -> [Image] {
        infos.map { info in
            let size = reader.textSegmentSize(imageBase: info.baseAddress) ?? 0
            let isUser = isUserImage(info.path)
            var json: [String: Any] = [
                "module": (info.path as NSString).lastPathComponent,
                "name": info.path,
                "addr": Int(info.baseAddress),
                "size": Int(size),
                "uuid": info.uuid?.uuidString ?? "",
            ]
            if let arch = archName(cpuType: info.cpuType, cpuSubType: info.cpuSubType) {
                json["arch"] = arch
            }
            // `_formatBinaryImages` writes the key only for user images.
            if isUser {
                json["user"] = true
            }
            return Image(base: info.baseAddress, size: size, isUser: isUser, json: json)
        }
        .sorted { $0.base < $1.base }
    }

    /// `isUserImage` in BGSCrashReport.m: anything inside the `.app` bundle, except the
    /// Swift runtime dylibs Xcode used to embed, which never come with a dSYM.
    private static func isUserImage(_ path: String) -> Bool {
        let lowercased = path.lowercased()
        guard lowercased.contains(".app/") else { return false }
        return !(lowercased.contains("frameworks/libswift") && lowercased.hasSuffix(".dylib"))
    }

    private static func archName(cpuType: cpu_type_t, cpuSubType: cpu_subtype_t) -> String? {
        guard cpuType == CPU_TYPE_ARM64 else { return nil }
        return (UInt32(bitPattern: cpuSubType) & 0x00FF_FFFF) == 2 ? "arm64e" : "arm64"
    }

    private static func image(containing address: UInt64, in images: [Image]) -> Image? {
        guard let candidate = images.last(where: { $0.base <= address }),
              candidate.contains(address) else { return nil }
        return candidate
    }

    /// The greatest of the ascending `starts` at or below `address`.
    private static func functionStart(of address: UInt64, in starts: [UInt64]) -> UInt64? {
        var low = 0
        var high = starts.count
        while low < high {
            let middle = (low + high) / 2
            if starts[middle] <= address {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low == 0 ? nil : starts[low - 1]
    }

    // MARK: - Threads

    /// The kernel's crashed-thread id matched through `THREAD_IDENTIFIER_INFO`. Failing
    /// that, the one thread whose pc sits in an app image; failing that, thread 0.
    ///
    /// Thread 0 is not assumed: a background jetsam had thread 0 in `mach_msg2_trap` and the
    /// allocator elsewhere. For a jetsam the kernel names the thread that crossed the limit —
    /// the last allocation, not necessarily the owner of the memory.
    private static func crashedThreadNumber(_ threads: [CorpseReader.Thread],
                                            info: CorpseReader.CrashInfo,
                                            images: [Image]) -> Int {
        if let id = info.crashedThreadID,
           let match = threads.first(where: { $0.identifier == id }) {
            return match.number
        }
        let inApp = threads.filter { thread in
            thread.frames.first.flatMap { image(containing: $0, in: images) }?.isUser == true
        }
        return inApp.count == 1 ? inApp[0].number : 0
    }

    /// `symbol + offset` for every frame outside the app bundle, looked up at the call
    /// site: a return address points past the call, so non-top frames step back one
    /// instruction first, as the SDK's own on-device symbolication does.
    private static func systemTraces(_ threads: [CorpseReader.Thread],
                                     images: [Image],
                                     process: CrashedProcess) -> [UInt64: String] {
        var lookups: [UInt64: UInt64] = [:]
        for thread in threads {
            for (index, address) in thread.frames.enumerated() {
                guard let image = image(containing: address, in: images), !image.isUser else { continue }
                if lookups[address] == nil {
                    lookups[address] = index == 0 ? address : address - ((address & 1) != 0 ? 1 : 4)
                }
            }
        }
        let addresses = Array(lookups.keys)
        let results = process.symbolicateAddresses(addresses.map { lookups[$0]! })
        var traces: [UInt64: String] = [:]
        for (address, symbols) in zip(addresses, results) {
            guard let symbol = symbols.first, !symbol.symbol.isEmpty else { continue }
            traces[address] = "\(symbol.symbol) + \(symbol.symbolOffset)"
        }
        return traces
    }
}

// MARK: - Output

@available(iOS 27.0, *)
extension CorpseReport {
    /// The group id lives once, in this appex's Info.plist (`BugseeAppGroup`); the SDK finds
    /// the appex by extension point and reads the same key, so the host configures nothing in
    /// code. Both targets must carry the group in their entitlements, or the URL is nil.
    private static func folder() -> URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "BugseeAppGroup") as? String,
              let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: group) else {
            logger.error("no App Group container: BugseeAppGroup missing or not entitled")
            return nil
        }
        return container.appendingPathComponent("Library/Bugsee", isDirectory: true)
    }

    /// `corpse-<start>-<pid>.json`, the dead process's start time zero-padded so the names
    /// sort by it; the time of writing when the corpse had none.
    private static func documentName(startTime: Int64?, pid: Int32?) -> String {
        let start = startTime ?? Int64(Date().timeIntervalSince1970 * 1_000_000)
        return "corpse-\(String(format: "%020lld", start))-\(pid ?? 0).json"
    }

    /// Atomic, so the SDK never reads half a document; the SDK deletes each one it reads.
    private static func save(_ document: [String: Any], name: String) {
        guard let folder = folder()?.appendingPathComponent("corpses", isDirectory: true) else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            trace("written \(data.count) bytes to \(name)")
            keepNewestDocuments(in: folder)
        } catch {
            trace("write failed: \(error)")
        }
    }

    private static func keepNewestDocuments(in folder: URL) {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasPrefix("corpse-") && $0.hasSuffix(".json") }
            .sorted()
        for name in names.dropLast(documentLimit) {
            do {
                try FileManager.default.removeItem(at: folder.appendingPathComponent(name))
                trace("dropped \(name): over \(documentLimit) documents")
            } catch {
                trace("drop of \(name) failed: \(error)")
            }
        }
    }

    /// One line per stage to the unified log and, in Debug builds, to
    /// `Library/Bugsee/crash-extension.log`, so a run the system cuts off mid-gather still
    /// leaves a record. Diagnostic only; the SDK never reads it. About five lines per death;
    /// past `logLimit` the older half goes. Not written in Release: the customer compiles this
    /// library into their extension, and a shipped app should not keep a diagnostic file in
    /// its App Group.
    private static func trace(_ line: String) {
        logger.log("\(line, privacy: .public)")
        #if DEBUG
        appendToLogFile(line)
        #endif
    }

    #if DEBUG
    private static func appendToLogFile(_ line: String) {
        guard let folder = folder() else { return }
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("crash-extension.log")
        let text = "\(ISO8601DateFormatter().string(from: Date())) pid=\(getpid()) \(line)\n"
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.write(contentsOf: data)
            try? handle.close()
            if size > logLimit {
                keepNewestHalf(ofLog: url)
            }
        } else {
            try? data.write(to: url)
        }
    }

    /// Rewrites the log with its last `logLimit / 2` bytes, cut after the first newline in them.
    private static func keepNewestHalf(ofLog url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let tail = data.suffix(Int(logLimit / 2))
        let newline = tail.firstIndex(of: UInt8(ascii: "\n"))
        let start = newline.map(tail.index(after:)) ?? tail.startIndex
        try? Data(tail[start...]).write(to: url, options: .atomic)
    }
    #endif
}

#endif
