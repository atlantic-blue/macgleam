// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacGleam",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "GleamCore", targets: ["GleamCore"]),
        .library(name: "GleamDesign", targets: ["GleamDesign"]),
        .library(name: "GleamHub", targets: ["GleamHub"]),
        .executable(name: "MacGleam", targets: ["MacGleam"])
    ],
    targets: [
        .target(
            name: "GleamDesign",
            path: "Sources/GleamDesign"
        ),
        .testTarget(
            name: "GleamDesignTests",
            dependencies: ["GleamDesign"],
            path: "Tests/GleamDesignTests"
        ),
        .target(
            name: "GleamCore",
            path: "Sources/GleamCore"
        ),
        .testTarget(
            name: "GleamCoreTests",
            dependencies: ["GleamCore"],
            path: "Tests/GleamCoreTests"
        ),
        .target(
            name: "CleanupEngine",
            dependencies: ["GleamCore"],
            path: "Sources/CleanupEngine"
        ),
        .testTarget(
            name: "CleanupEngineTests",
            dependencies: ["CleanupEngine", "GleamCore"],
            path: "Tests/CleanupEngineTests"
        ),
        .target(
            name: "ClutterEngine",
            dependencies: ["GleamCore"],
            path: "Sources/ClutterEngine"
        ),
        .testTarget(
            name: "ClutterEngineTests",
            dependencies: ["ClutterEngine", "GleamCore"],
            path: "Tests/ClutterEngineTests"
        ),
        .target(
            name: "CleanupModule",
            dependencies: ["GleamCore", "CleanupEngine"],
            path: "Sources/CleanupModule"
        ),
        .testTarget(
            name: "CleanupModuleTests",
            dependencies: ["CleanupModule", "CleanupEngine", "GleamCore"],
            path: "Tests/CleanupModuleTests"
        ),
        .target(
            name: "SpaceLensEngine",
            dependencies: ["GleamCore"],
            path: "Sources/SpaceLensEngine"
        ),
        .testTarget(
            name: "SpaceLensEngineTests",
            dependencies: ["SpaceLensEngine", "GleamCore"],
            path: "Tests/SpaceLensEngineTests"
        ),
        .target(
            name: "SpaceLensModule",
            dependencies: ["GleamCore", "SpaceLensEngine", "GleamHub"],
            path: "Sources/SpaceLensModule"
        ),
        .testTarget(
            name: "PerformanceGateTests",
            dependencies: ["GleamCore", "CleanupEngine", "SpaceLensEngine"],
            path: "Tests/PerformanceGateTests"
        ),
        .testTarget(
            name: "SpaceLensModuleTests",
            dependencies: ["SpaceLensModule", "SpaceLensEngine", "GleamCore", "GleamHub", "GleamDesign"],
            path: "Tests/SpaceLensModuleTests"
        ),
        .target(
            name: "GleamHub",
            dependencies: ["GleamDesign"],
            path: "Sources/GleamHub"
        ),
        .testTarget(
            name: "GleamHubTests",
            dependencies: ["GleamHub", "GleamDesign"],
            path: "Tests/GleamHubTests"
        ),
        .executableTarget(
            name: "GleamBaselineGenerator",
            dependencies: ["GleamCore"],
            path: "Sources/GleamBaselineGenerator"
        ),
        .executableTarget(
            name: "MacGleam",
            dependencies: [
        "GleamHub", "GleamDesign", "GleamCore", "CleanupEngine", "CleanupModule",
        "SpaceLensEngine", "SpaceLensModule",
      ],
            path: "Sources/MacGleam"
        )
    ]
)
