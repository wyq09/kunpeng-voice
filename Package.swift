// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "CloneVoice",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "CloneVoice", targets: ["CloneVoice"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/Blaizzy/mlx-audio-swift.git",
            revision: "dbe5eaac964e8257785f9d015c81f819a38016a8"
        ),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", .upToNextMajor(from: "0.30.6")),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", .upToNextMajor(from: "0.8.1")),
        .package(path: "Vendor/SpeechSwift"),
    ],
    targets: [
        .executableTarget(
            name: "CloneVoice",
            dependencies: [
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "CosyVoiceTTS", package: "SpeechSwift"),
                .product(name: "VoxCPM2TTS", package: "SpeechSwift"),
            ],
            path: "Sources/CloneVoice",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
