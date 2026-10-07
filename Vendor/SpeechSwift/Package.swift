// swift-tools-version:5.10
// CosyVoice 3 and VoxCPM 2 MLX runtimes vendored from https://github.com/soniqo/speech-swift
// (commit cbcdfc6, Apache-2.0) to avoid that package's conflicting mlx-swift-lm pin.
// Local changes are marked "CloneVoice patch".
import PackageDescription

let package = Package(
    name: "SpeechSwift",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "CosyVoiceTTS", targets: ["CosyVoiceTTS"]),
        .library(name: "VoxCPM2TTS", targets: ["VoxCPM2TTS"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.30.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.1.6"),
    ],
    targets: [
        .target(
            name: "AudioCommon",
            dependencies: [.product(name: "Hub", package: "swift-transformers")]
        ),
        .target(
            name: "MLXCommon",
            dependencies: [
                "AudioCommon",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXFFT", package: "mlx-swift"),
            ]
        ),
        .target(
            name: "CosyVoiceTTS",
            dependencies: [
                "AudioCommon",
                "MLXCommon",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
            ]
        ),
        .target(
            name: "VoxCPM2TTS",
            dependencies: [
                "AudioCommon",
                "MLXCommon",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "Transformers", package: "swift-transformers"),
            ]
        ),
    ]
)
