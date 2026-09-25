// swift-tools-version: 6.0
import PackageDescription

let strictSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "OpenWallpaperMac",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "OWAppFeature", targets: ["OWAppFeature"]),
        .executable(name: "owctl", targets: ["owctl"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "OWCore", swiftSettings: strictSettings),
        .target(name: "OWFormats", dependencies: ["OWCore"], swiftSettings: strictSettings),
        .target(name: "OWAudioAnalysis", swiftSettings: strictSettings),
        .target(
            name: "OWAudioCapture",
            dependencies: ["OWCore", "OWAudioAnalysis"],
            swiftSettings: strictSettings
        ),
        .target(name: "OWPower", dependencies: ["OWCore"], swiftSettings: strictSettings),
        .target(name: "OWDesktop", dependencies: ["OWCore"], swiftSettings: strictSettings),
        .target(
            name: "OWRendering",
            dependencies: ["OWCore", "OWFormats"],
            swiftSettings: strictSettings
        ),
        .target(
            name: "OWScene",
            dependencies: ["OWCore", "OWFormats", "OWRendering"],
            swiftSettings: strictSettings
        ),
        .target(name: "OWLibrary", dependencies: ["OWCore", "OWFormats"], swiftSettings: strictSettings),
        .target(
            name: "OWAppFeature",
            dependencies: [
                "OWCore", "OWFormats", "OWAudioAnalysis", "OWAudioCapture", "OWPower",
                "OWDesktop", "OWRendering", "OWScene", "OWLibrary",
            ],
            swiftSettings: strictSettings
        ),
        .executableTarget(
            name: "owctl",
            dependencies: [
                "OWCore", "OWFormats", "OWLibrary", "OWRendering", "OWScene",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: strictSettings
        ),
        .testTarget(name: "OWCoreTests", dependencies: ["OWCore"]),
        .testTarget(name: "OWFormatsTests", dependencies: ["OWFormats", "OWCore"]),
        .testTarget(name: "OWAudioAnalysisTests", dependencies: ["OWAudioAnalysis"]),
        .testTarget(name: "OWPowerTests", dependencies: ["OWPower", "OWCore"]),
        .testTarget(name: "OWDesktopTests", dependencies: ["OWDesktop", "OWCore"]),
        .testTarget(name: "OWRenderingTests", dependencies: ["OWRendering", "OWCore", "OWFormats"]),
        .testTarget(name: "OWSceneTests", dependencies: ["OWScene", "OWRendering", "OWFormats", "OWCore"]),
        .testTarget(name: "OWLibraryTests", dependencies: ["OWLibrary", "OWFormats", "OWCore"]),
        .testTarget(name: "OWAppFeatureTests", dependencies: ["OWAppFeature", "OWPower", "OWCore"]),
    ]
)
