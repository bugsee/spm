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
            url: "https://download.bugsee.com/sdk/ios/spm/Bugsee-1.28.5.zip",
            checksum: "1e4d282c9f7e9f3c8669c149d6b86e742a08533a8f7aaed52ed9f4ea7ec2bf47")
    ]
)
