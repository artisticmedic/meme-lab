// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MemeLab",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "meme", targets: ["meme"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "MemeCore"),
        .executableTarget(
            name: "meme",
            dependencies: [
                "MemeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "MemeCoreTests", dependencies: ["MemeCore"]),
    ]
)
