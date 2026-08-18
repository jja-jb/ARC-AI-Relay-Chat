// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ARC",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ARCDesktop", targets: ["ARCApp"]),
        .executable(name: "arc", targets: ["ARCCommand"]),
        .executable(name: "arc-dev", targets: ["ARCDevTool"]),
        .library(name: "ARCCore", targets: ["ARCCore"]),
    ],
    targets: [
        .target(
            name: "ARCKnowledge",
            path: "knowledge",
            exclude: ["tests"],
            sources: ["src/arc_knowledge.c"],
            publicHeadersPath: "include"
        ),
        .target(
            name: "ARCCore",
            dependencies: ["ARCKnowledge"],
            path: "app/Sources/ARCCore"
        ),
        .executableTarget(
            name: "ARCCommand",
            dependencies: ["ARCCore"],
            path: "app/Sources/ARCCommand"
        ),
        .executableTarget(
            name: "ARCDevTool",
            dependencies: ["ARCKnowledge"],
            path: "Sources/ARCDevTool"
        ),
        .executableTarget(
            name: "ARCApp",
            dependencies: ["ARCCore"],
            path: "app/Sources/ARCApp",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "ARCCoreTests",
            dependencies: ["ARCCore"],
            path: "app/Tests/ARCCoreTests"
        ),
        .testTarget(
            name: "ARCAppTests",
            dependencies: ["ARCApp", "ARCCore"],
            path: "app/Tests/ARCAppTests"
        ),
    ]
)
