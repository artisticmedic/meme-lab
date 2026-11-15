// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MemeLab",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "MemeLab", targets: ["MemeLab"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "MemeCore"),
        .target(
            name: "MemeCLI",
            dependencies: [
                "MemeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(name: "MemeLab", dependencies: ["MemeCore", "MemeCLI"]),
        .testTarget(name: "MemeCoreTests", dependencies: ["MemeCore", "MemeCLI"]),
    ]
)
