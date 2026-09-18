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
        .library(name: "BugseeSwiftUI", targets: ["Bugsee", "BugseeSwiftUI"])
    ],
    targets: [
        .binaryTarget(
            name: "Bugsee",
            url: "https://download.bugsee.com/sdk/ios/spm/Bugsee-7.0.0-beta2.zip",
            checksum: "4698b961d5ce77b1bb0a13765d508c8faa1b746d06cbe0b89cfbc10b71114564"),
        .target(
            name: "BugseeSwiftUI",
            dependencies: ["Bugsee"],
            path: "Sources/BugseeSwiftUI")
    ]
)
