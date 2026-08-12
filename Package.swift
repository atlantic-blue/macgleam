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
        .executable(name: "MacGleam", targets: ["MacGleam"]),
        .executable(name: "GleamHelper", targets: ["GleamHelper"])
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
            name: "GleamHelperCore",
            dependencies: ["GleamCore"],
            path: "Sources/GleamHelperCore"
        ),
        .testTarget(
            name: "GleamHelperCoreTests",
            dependencies: ["GleamHelperCore", "GleamCore"],
            path: "Tests/GleamHelperCoreTests"
        ),
        .target(
            name: "GleamHelperClient",
            dependencies: ["GleamCore", "GleamHelperCore"],
            path: "Sources/GleamHelperClient"
        ),
        .testTarget(
            name: "GleamHelperClientTests",
            dependencies: ["GleamHelperClient", "GleamHelperCore", "GleamCore"],
            path: "Tests/GleamHelperClientTests"
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
            name: "LeftoversEngine",
            dependencies: ["GleamCore"],
            path: "Sources/LeftoversEngine"
        ),
        .testTarget(
            name: "LeftoversEngineTests",
            dependencies: ["LeftoversEngine", "GleamCore"],
            path: "Tests/LeftoversEngineTests"
        ),
        .target(
            name: "CleanupModule",
            dependencies: ["GleamCore", "CleanupEngine", "GleamHub"],
            path: "Sources/CleanupModule"
        ),
        .testTarget(
            name: "CleanupModuleTests",
            dependencies: ["CleanupModule", "CleanupEngine", "GleamCore", "GleamHub"],
            path: "Tests/CleanupModuleTests"
        ),
        .target(
            name: "DiskMapEngine",
            dependencies: ["GleamCore"],
            path: "Sources/DiskMapEngine"
        ),
        .testTarget(
            name: "DiskMapEngineTests",
            dependencies: ["DiskMapEngine", "GleamCore"],
            path: "Tests/DiskMapEngineTests"
        ),
        .target(
            name: "PerformanceEngine",
            dependencies: ["GleamCore"],
            path: "Sources/PerformanceEngine"
        ),
        .testTarget(
            name: "PerformanceEngineTests",
            dependencies: ["PerformanceEngine", "GleamCore"],
            path: "Tests/PerformanceEngineTests"
        ),
        .target(
            name: "ProtectionEngine",
            dependencies: ["GleamCore"],
            path: "Sources/ProtectionEngine"
        ),
        .testTarget(
            name: "ProtectionEngineTests",
            dependencies: ["ProtectionEngine", "GleamCore"],
            path: "Tests/ProtectionEngineTests"
        ),
        .target(
            name: "ApplicationsEngine",
            dependencies: ["GleamCore"],
            path: "Sources/ApplicationsEngine"
        ),
        .testTarget(
            name: "ApplicationsEngineTests",
            dependencies: ["ApplicationsEngine", "GleamCore", "GleamHelperCore"],
            path: "Tests/ApplicationsEngineTests"
        ),
        .target(
            name: "DiskMapModule",
            dependencies: ["GleamCore", "DiskMapEngine", "GleamHub"],
            path: "Sources/DiskMapModule"
        ),
        .testTarget(
            name: "PerformanceGateTests",
            dependencies: ["GleamCore", "CleanupEngine", "DiskMapEngine"],
            path: "Tests/PerformanceGateTests"
        ),
        .testTarget(
            name: "DiskMapModuleTests",
            dependencies: ["DiskMapModule", "DiskMapEngine", "GleamCore", "GleamHub", "GleamDesign"],
            path: "Tests/DiskMapModuleTests"
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
            name: "GleamHelper",
            dependencies: ["GleamCore", "GleamHelperCore"],
            path: "Sources/GleamHelper"
        ),
        .executableTarget(
            name: "GleamRulesPublisher",
            dependencies: ["GleamCore"],
            path: "Sources/GleamRulesPublisher"
        ),
        .executableTarget(
            name: "GleamBaselineGenerator",
            dependencies: ["GleamCore"],
            path: "Sources/GleamBaselineGenerator"
        ),
        .executableTarget(
            name: "GleamBundler",
            path: "Sources/GleamBundler"
        ),
        .executableTarget(
            name: "MacGleam",
            dependencies: [
        "GleamHub", "GleamDesign", "GleamCore", "GleamHelperCore", "GleamHelperClient",
        "CleanupEngine", "CleanupModule", "DiskMapEngine", "DiskMapModule",
      ],
            path: "Sources/MacGleam"
        )
    ]
)
