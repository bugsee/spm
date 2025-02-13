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
            url: "https://download.bugsee.com/sdk/ios/spm/Bugsee-5.5.5.zip",
            checksum: "7fce12695f5ad827d65f1e44c6f7f6c6173deadb48445b3ebe2f8c3a6f12c163")
    ]
)
