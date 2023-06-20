// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Bugsee",
    products: [
        .library(
            name: "Bugsee",
            targets: ["Bugsee"])
    ],
    targets: [
        .binaryTarget(
            name: "Bugsee",
            url: "https://download.bugsee.com/sdk/ios/spm/Bugsee-3.6.2.zip",
            checksum: "2c41a3f100fcb2b4160fbbfc38b0d9ec2d2aa7bd1b359ecfbc5ef8da993cfa00")
    ]
)
