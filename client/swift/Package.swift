// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "GradioClient",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "GradioClient",
            targets: ["GradioClient"]
        ),
        .executable(
            name: "GradioClientCLI",
            targets: ["GradioClientCLI"]
        )
    ],
    targets: [
        .target(
            name: "GradioClient",
            path: "Sources/GradioClient"
        ),
        .executableTarget(
            name: "GradioClientCLI",
            dependencies: ["GradioClient"],
            path: "Sources/GradioClientCLI"
        ),
        .testTarget(
            name: "GradioClientTests",
            dependencies: ["GradioClient"],
            path: "Tests"
        )
    ]
)
