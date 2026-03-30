// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "clean-my-mac",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "CleanMyMac",
            targets: ["CleanMyMacApp"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "CleanMyMacApp",
            path: "Sources/clean-my-mac"
        ),
        .testTarget(
            name: "CleanMyMacAppTests",
            dependencies: ["CleanMyMacApp"]
        ),
    ]
)
