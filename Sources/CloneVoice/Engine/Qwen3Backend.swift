import Foundation
import MLX
import MLXAudioCore
import MLXAudioTTS

func releaseGPUMemory() { Memory.clearCache() }

final class Qwen3Backend: CloneBackend {
    private let model: Qwen3TTSModel

    var sampleRate: Int { model.sampleRate }

    init(directory: URL) async throws {
        model = try await Qwen3TTSModel.fromModelDirectory(directory)
        // First inference JIT-compiles GPU kernels; pay that cost while the UI still says "loading".
        _ = try? await model.generate(text: "你好。", voice: nil, refAudio: nil, refText: nil, language: "chinese")
    }

    /// Clone mode ignores text instructions, so style only steers sampling here.
    /// The language is pinned per voice: guessing it per sentence makes the accent drift.
    func generate(
        text: String, sampleURL: URL, referenceText: String, language: VoiceLanguage, style: SpeechStyle,
        faithful: Bool
    ) async throws -> [Float] {
        let (_, refAudio) = try loadAudioArray(from: sampleURL, sampleRate: model.sampleRate)
        var parameters = model.defaultGenerationParameters
        parameters.temperature = faithful ? min(style.prosody.temperature, 0.6) : style.prosody.temperature
        let audio = try await model.generate(
            text: text,
            voice: nil,
            refAudio: refAudio,
            refText: referenceText,
            language: language.rawValue,
            generationParameters: parameters
        )
        return audio.asArray(Float.self)
    }
}
