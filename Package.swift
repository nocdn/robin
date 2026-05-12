// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "robin",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "robin", targets: ["robin"])
    ],
    targets: [
        .executableTarget(
            name: "robin",
            path: "Sources/robin"
        )
    ]
)
