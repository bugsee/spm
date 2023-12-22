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
            url: "https://download.bugsee.com/sdk/ios/spm/Bugsee-5.0.0.zip",
            checksum: "6c7545b449f94b8aa626218a175927ffae600809cf24af97826ee1b82a4c8f13")
    ]
)
