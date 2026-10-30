//
//  BugseeCrashReporterExtension.swift
//  BugseeCrashExtension
//
//  Copyright © 2026 Bugsee. All rights reserved.
//

// The real extension needs the iOS 27 device SDK. The iOS Simulator SDK and older SDKs have
// no CrashReportExtension; the tvOS SDK has the module but marks the protocol unavailable,
// and the extension supports iOS only. Everywhere else the stub below keeps the host's
// `@main` compiling.
#if os(iOS) && canImport(CrashReportExtension)

// Re-exported: the host's `import BugseeCrashExtension` must also bring in the members the
// system's protocols get from extensions (`configuration`, `main()`). Under
// `MemberImportVisibility`, which Xcode 27 projects enable, those are not visible otherwise
// and the conformance fails ("does not conform to protocol 'AppExtension'").
@_exported import CrashReportExtension

/// The whole Crash Reporter Extension a Bugsee host app needs:
///
/// ```swift
/// import BugseeCrashExtension
///
/// @main struct CrashReport: BugseeCrashReporterExtension {}
/// ```
///
/// The system starts the extension in a process of its own once the app has died and the
/// kernel kept a corpse: crash signals, per-process-limit jetsam, the launch watchdog,
/// code-signing kills. It is not called for a suspended app evicted under memory pressure,
/// and only one crash-reporter extension per app runs for each crash.
///
/// The extension runs next to the SDK's in-process crash reporter, not instead of it: for a
/// signal crash both write and the SDK keeps its own report. What only the extension sees are
/// the deaths no in-process handler survives (SIGKILL): jetsam, watchdog, code signing.
///
/// `processCrashReport(process:)` reads the threads, the exit reason and the binary images
/// out of the corpse and writes one JSON document into the App Group that the extension's
/// Info.plist names under `BugseeAppGroup`. The SDK reads and deletes it on the app's next
/// launch. Nothing leaves the device from the extension. The system kills the extension
/// after a few seconds, so the work stays well under a second: no upload, no heap scan.
///
/// Do not implement `processCrashReport(process:)` in the conforming type: that replaces
/// Bugsee's.
@available(iOS 27.0, *)
public protocol BugseeCrashReporterExtension: CrashReporterExtension {}

@available(iOS 27.0, *)
extension BugseeCrashReporterExtension {
    /// Writes the document for the SDK. `process` is valid only during this call.
    ///
    /// The system calls it on an XPC queue, not the main thread. `nonisolated` keeps it there
    /// even in a module whose default actor isolation is `MainActor`.
    public nonisolated func processCrashReport(process: CrashedProcess) {
        CorpseReport.write(for: process)
    }
}

#else

/// Stands in for the real protocol where the CrashReportExtension module is missing (the iOS
/// Simulator, SDKs older than iOS 27), so a host app's extension target still builds there.
/// The system never launches such a build.
public protocol BugseeCrashReporterExtension {
    init()
}

extension BugseeCrashReporterExtension {
    /// The `@main` entry point of the stub. Returns at once.
    public static func main() {}
}

#endif
