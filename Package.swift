// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Bugsee",
    platforms: [
        .iOS(.v12)
    ],
    products: [
        .library(name: "Bugsee", targets: ["Bugsee"]),
        .library(name: "BugseeSwiftUI", targets: ["Bugsee", "BugseeSwiftUI"])
    ],
    targets: [
        .binaryTarget(
            name: "Bugsee",
            url: "https://download.bugsee.com/sdk/ios/spm/Bugsee-6.2.1.zip",
            checksum: "4c3114385d1f6d4696077391bb93b0e3d3e559a684ff19909d2c9a13a316cf60"),
        .target(
            name: "BugseeSwiftUI",
            dependencies: ["Bugsee"],
            path: "Sources/BugseeSwiftUI")
    ]
)
