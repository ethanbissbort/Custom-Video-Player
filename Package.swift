// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CustomVideoPlayer",
    // Required before SwiftPM will accept localized resources (Resources/en.lproj).
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "CustomVideoPlayer",
            targets: ["CustomVideoPlayer"]
        ),
    ],
    dependencies: [
        .package(name: "SnapKit", url: "https://github.com/SnapKit/SnapKit.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "CustomVideoPlayer",
            dependencies: [
                "SnapKit"
            ],
            path: "Custom-Video-Player",
            resources: [
                .process("Assets/Color.xcassets"),
                .process("Assets/Images.xcassets"),
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CustomVideoPlayerTests",
            dependencies: ["CustomVideoPlayer"],
            path: "Tests/CustomVideoPlayerTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
