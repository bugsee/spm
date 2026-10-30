// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Bugsee",
    platforms: [
        .iOS(.v15),
        .tvOS(.v15),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "Bugsee", targets: ["Bugsee"]),
        .library(name: "BugseeSwiftUI", targets: ["Bugsee", "BugseeSwiftUI"]),
        .library(name: "BugseeCrashExtension", targets: ["BugseeCrashExtension"])
    ],
    targets: [
        .binaryTarget(
            name: "Bugsee",
            url: "https://download.bugsee.com/sdk/ios/spm/Bugsee-7.0.0.zip",
            checksum: "34a03858b8b0a5a3cf23deafea90acd7b880590a59754887214745013f60974a"),
        .target(
            name: "BugseeSwiftUI",
            dependencies: ["Bugsee"],
            path: "Sources/BugseeSwiftUI"),
        // Linked only by the app's Crash Reporter Extension target (iOS 27+). It does not
        // link the core SDK: the app reads what the extension writes.
        .target(
            name: "BugseeCrashExtension",
            path: "Sources/BugseeCrashExtension")
    ]
)
