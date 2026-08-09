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
            dependencies: ["GleamHub", "GleamDesign"],
            path: "Sources/MacGleam"
        )
    ]
)
