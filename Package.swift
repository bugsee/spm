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
            url: "https://download.bugsee.com/sdk/ios/spm/Bugsee-4.0.0.zip",
            checksum: "a5ba32daa8d3a998bc0f9e3c09fb3b9625da20f5832218fe9a6f0d88eeefe999")
    ]
)
