import Foundation

struct ModelSpec: Identifiable, Hashable {
    enum Family { case qwen3, cosyVoice, voxCPM2, voxCPM15 }

    /// Hugging Face repository ID.
    let id: String
    let family: Family
    let name: String
    let detail: String
    let sizeBytes: Int64
    var isRecommended = false

    var supportsEmotionInstruction: Bool { family == .cosyVoice || family == .voxCPM2 }
    var folderName: String { id.replacingOccurrences(of: "/", with: "_") }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file) }

    var downloadPatterns: [String] {
        switch family {
        case .qwen3: ["*.safetensors", "*.json", "*.txt", "*.wav"]
        case .cosyVoice: ["*.safetensors", "*.json", "*.txt", "*.bin"]
        case .voxCPM2, .voxCPM15: ["*.safetensors", "*.json"]
        }
    }

    /// Chinese characters per generation call; longer inputs drift in voice and content.
    var chunkLength: Int {
        switch family {
        case .qwen3: 120
        case .cosyVoice: 60
        case .voxCPM2, .voxCPM15: 150
        }
    }
}

enum ModelCatalog {
    static let all: [ModelSpec] = [
        ModelSpec(
            id: "aufklarer/CosyVoice3-0.5B-MLX-8bit-full",
            family: .cosyVoice,
            name: "CosyVoice 3",
            detail: "阿里通义 · 情绪指令真正生效，中文自然",
            sizeBytes: 1_610_000_000,
            isRecommended: true
        ),
        ModelSpec(
            id: "aufklarer/CosyVoice3-0.5B-MLX-4bit",
            family: .cosyVoice,
            name: "CosyVoice 3 轻量版",
            detail: "4bit 量化 · 更小更快，音质略降",
            sizeBytes: 1_260_000_000
        ),
        ModelSpec(
            id: "mlx-community/VoxCPM2-4bit",
            family: .voxCPM2,
            name: "VoxCPM 2",
            detail: "面壁智能 · 48kHz 高保真，支持风格描述",
            sizeBytes: 2_300_000_000
        ),
        ModelSpec(
            id: "mlx-community/VoxCPM1.5-8bit",
            family: .voxCPM15,
            name: "VoxCPM 1.5",
            detail: "面壁智能 · 44.1kHz，体积小 · 情绪为近似效果",
            sizeBytes: 1_030_000_000
        ),
        ModelSpec(
            id: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit",
            family: .qwen3,
            name: "Qwen3-TTS 1.7B",
            detail: "音色还原度高 · 情绪为近似效果",
            sizeBytes: 3_100_000_000
        ),
        ModelSpec(
            id: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",
            family: .qwen3,
            name: "Qwen3-TTS 0.6B",
            detail: "生成更快 · 情绪为近似效果",
            sizeBytes: 1_990_000_000
        ),
    ]

    static let defaultModel = all[0]

    static func spec(id: String) -> ModelSpec? { all.first { $0.id == id } }
}
