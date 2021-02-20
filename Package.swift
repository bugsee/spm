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
            url: "https://download.bugsee.com/sdk/ios/Bugsee-1.27.1.zip",
            checksum: "13f51e3084c735395839ac67bc0b241830b7265b60c6aac88955192c0f27073e")
    ]
)
