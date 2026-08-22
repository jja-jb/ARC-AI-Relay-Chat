// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [
    .executable(name: "arc", targets: ["ARCCommand"]),
    .executable(name: "arc-admin", targets: ["ARCAdmin"]),
    .executable(name: "arc-dev", targets: ["ARCDevTool"]),
    .library(name: "ARCCore", targets: ["ARCCore"]),
]

var targets: [Target] = [
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
        name: "ARCAdmin",
        dependencies: ["ARCCore"],
        path: "linux/Sources/ARCAdmin"
    ),
    .executableTarget(
        name: "ARCDevTool",
        dependencies: ["ARCKnowledge"],
        path: "Sources/ARCDevTool"
    ),
    .testTarget(
        name: "ARCCoreTests",
        dependencies: ["ARCCore"],
        path: "app/Tests/ARCCoreTests"
    ),
]

#if os(macOS)
products += [
    .executable(name: "ARCDesktop", targets: ["ARCApp"]),
]
targets += [
    .executableTarget(
        name: "ARCApp",
        dependencies: ["ARCCore"],
        path: "app/Sources/ARCApp",
        resources: [.copy("PrivacyInfo.xcprivacy")]
    ),
    .testTarget(
        name: "ARCAppTests",
        dependencies: ["ARCApp", "ARCCore"],
        path: "app/Tests/ARCAppTests"
    ),
]
#endif

let package = Package(
    name: "ARC",
    platforms: [.macOS(.v15)],
    products: products,
    targets: targets
)
