// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Bugsee",
    products: [
        .library(
            name: "Bugsee",
            type: .static,
            targets: ["Bugsee"])
    ],
    targets: [
        .binaryTarget(
            name: "Bugsee",
            url: "https://download.bugsee.com/sdk/ios/Bugsee-1.27.0.zip",
            checksum: "e86eb7b211da4408cceffbc738e9e9929e2e76bb09c692d5f95ce34e3acee273")
    ]
)
