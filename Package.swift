// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacGleam",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "GleamDesign", targets: ["GleamDesign"])
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
        )
    ]
)
