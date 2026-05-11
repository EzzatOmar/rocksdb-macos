// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RocksDBViewer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "RocksDBViewer", targets: ["RocksDBViewer"])
    ],
    targets: [
        .executableTarget(
            name: "RocksDBViewer",
            path: "Sources/RocksDBViewer"
        ),
        .testTarget(
            name: "RocksDBViewerTests",
            dependencies: ["RocksDBViewer"],
            path: "Tests/RocksDBViewerTests"
        )
    ]
)
