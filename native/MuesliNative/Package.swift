// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MuesliNative",
    platforms: [
        .macOS("14.2"),
    ],
    products: [
        .executable(name: "MuesliNativeApp", targets: ["MuesliNativeApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.2"),
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git", branch: "master"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "MuesliNativeApp",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "SwiftWhisper", package: "SwiftWhisper"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/MuesliNativeApp",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "MuesliTests",
            dependencies: ["MuesliNativeApp"],
            path: "Tests/MuesliTests",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
