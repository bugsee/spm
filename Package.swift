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
            url: "https://download.bugsee.com/sdk/ios/spm/Bugsee-6.1.1.zip",
            checksum: "98e1860354cc4ba35b1e462e9c9c0b0bf760ecc6e4a3c2752a0de7fa987c14dd")
    ]
)
