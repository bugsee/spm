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
            url: "https://download.bugsee.com/sdk/ios/spm/Bugsee-5.0.3.zip",
            checksum: "5cf2f8d72f325c0c6c1de7c0ea42e119a31581c88356d81a2ca656f5d10a6bc5")
    ]
)
