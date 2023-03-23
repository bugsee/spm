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
            url: "https://download.bugsee.com/sdk/ios/spm/Bugsee-3.4.1.zip",
            checksum: "6d57e74e6cb34c9af7f26cac2dd454fd53a16a7bbdb4fe2b6f9c806cfe110d49")
    ]
)
