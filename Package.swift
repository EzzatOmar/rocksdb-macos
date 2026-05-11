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
        .target(
            name: "CRocksBridge",
            path: "Sources/CRocksBridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(["-std=c++20", "-I/opt/homebrew/opt/rocksdb/include"])
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/opt/rocksdb/lib"]),
                .linkedLibrary("rocksdb"),
                .linkedLibrary("c++")
            ]
        ),
        .executableTarget(
            name: "RocksDBViewer",
            dependencies: ["CRocksBridge"],
            path: "Sources/RocksDBViewer"
        ),
        .testTarget(
            name: "RocksDBViewerTests",
            dependencies: ["RocksDBViewer"],
            path: "Tests/RocksDBViewerTests"
        )
    ]
)
