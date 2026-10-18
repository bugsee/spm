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
            url: "https://download.bugsee.com/sdk/ios/spm/Bugsee-7.0.0-beta7.zip",
            checksum: "21b8209c2541c632b39085702e4b71930cf08673cbe05406cbd0b1783f87043b"),
        .target(
            name: "BugseeSwiftUI",
            dependencies: ["Bugsee"],
            path: "Sources/BugseeSwiftUI")
    ]
)
