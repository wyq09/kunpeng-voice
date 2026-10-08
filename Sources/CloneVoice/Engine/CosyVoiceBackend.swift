import CosyVoiceTTS
import Foundation

final class CosyVoiceBackend: CloneBackend {
    private let model: CosyVoiceTTSModel
    private let speechTokenizer: SpeechTokenizerModel
    /// Extracting a profile encodes the whole reference clip; reuse it while the voice stays the same.
    private var cachedProfile: (key: String, profile: CosyVoiceVoiceProfile)?

    let sampleRate = 24_000

    init(directory: URL, modelID: String) async throws {
        model = try await CosyVoiceTTSModel.fromPretrained(modelId: modelID, cacheDir: directory, offlineMode: true)
        speechTokenizer = try SpeechTokenizerModel.fromSafetensors(
            at: directory.appendingPathComponent("speech_tokenizer.safetensors")
        )
    }

    func generate(
        text: String, sampleURL: URL, referenceText: String, language: VoiceLanguage, style: SpeechStyle,
        faithful: Bool, previous _: SpokenChunk?
    ) async throws -> [Float] {
        let profile = try profile(for: sampleURL, referenceText: referenceText)
        // Instructions use CosyVoice's instruct2 layout, which hides the reference speech from the LLM.
        guard !faithful, let instruction = style.instruction else {
            return model.synthesize(text: text, voiceProfile: profile, language: language.rawValue)
        }
        return model.synthesize(text: text, voiceProfile: profile, language: language.rawValue, instruction: instruction)
    }

    private func profile(for sampleURL: URL, referenceText: String) throws -> CosyVoiceVoiceProfile {
        let key = sampleURL.path + "|" + referenceText
        if let cachedProfile, cachedProfile.key == key { return cachedProfile.profile }
        let profile = try model.extractVoiceProfile(
            audio: MonoAudioLoader.load(sampleURL, sampleRate: 24_000),
            sampleRate: 24_000,
            speechTokenizer: speechTokenizer,
            referenceTranscript: referenceText
        )
        cachedProfile = (key, profile)
        return profile
    }
}
