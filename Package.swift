// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "QwenDictate",
    platforms: [.macOS("15.0")],
    dependencies: [
        .package(url: "https://github.com/soniqo/speech-swift", from: "0.0.12"),
    ],
    targets: [
        .target(
            name: "QwenDictateCore",
            path: "Sources/QwenDictateCore"
        ),
        .executableTarget(
            name: "QwenDictate",
            dependencies: [
                .target(name: "QwenDictateCore"),
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "SpeechVAD", package: "speech-swift"),
                .product(name: "AudioCommon", package: "speech-swift"),
            ],
            path: "QwenDictate",
            exclude: ["QwenDictate.entitlements", "Info.plist"]
        ),
        .testTarget(
            name: "QwenDictateTests",
            dependencies: [
                .target(name: "QwenDictateCore"),
            ],
            path: "Tests"
        ),
    ]
)
