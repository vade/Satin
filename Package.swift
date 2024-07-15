// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "Satin",
    platforms: [.macOS(.v14), .iOS(.v13), .tvOS(.v13)],
    products: [
        .library(
            name: "SatinCore",
            targets: ["SatinCore"]
        ),
        .library(
            name: "Satin",
            targets: ["Satin"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SatinCore",
            path: "Sources/SatinCore",
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("include")],
            cxxSettings: [.headerSearchPath("include")]
        ),
        .testTarget(
            name: "SatinCoreTests",
            dependencies: ["SatinCore"]
        ),
        .target(
            name: "Satin",
            dependencies: ["SatinCore"],
            path: "Sources/Satin",
            resources: [.copy("Pipelines")]
        ),
        .testTarget(
            name: "SatinTests",
            dependencies: ["Satin"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
