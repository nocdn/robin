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
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.14.5")
    ],
    targets: [
        .executableTarget(
            name: "robin",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/robin"
        )
    ]
)
