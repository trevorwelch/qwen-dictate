// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DictateDemo",
    platforms: [.macOS("15.0")],
    dependencies: [
        .package(url: "https://github.com/soniqo/speech-swift", from: "0.0.12"),
    ],
    targets: [
        .executableTarget(
            name: "DictateDemo",
            dependencies: [
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "SpeechVAD", package: "speech-swift"),
                .product(name: "AudioCommon", package: "speech-swift"),
            ],
            path: "DictateDemo",
            exclude: ["DictateDemo.entitlements", "Info.plist"]
        ),
        .testTarget(
            name: "DictateDemoTests",
            dependencies: [
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "SpeechVAD", package: "speech-swift"),
                .product(name: "AudioCommon", package: "speech-swift"),
            ],
            path: "Tests"
        ),
    ]
)
