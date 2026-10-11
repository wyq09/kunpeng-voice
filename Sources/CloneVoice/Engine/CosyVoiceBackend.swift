import CosyVoiceTTS
import Foundation

final class CosyVoiceBackend: CloneBackend {
    /// A fixed seed per take keeps chunks of one script consistent in tone and pace; retries
    /// offset it so they actually sound different.
    private static let seed: UInt64 = 20_260_806

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
        faithful: Bool, previous _: SpokenChunk?, variant: Int
    ) async throws -> [Float] {
        let profile = try await profile(for: sampleURL, referenceText: referenceText)
        let seed = Self.seed &+ UInt64(variant)
        // Instructions use CosyVoice's instruct2 layout, which hides the reference speech from the
        // LLM, so it has no pace to follow; the instruction asks for a steady one instead.
        guard !faithful, let instruction = style.instruction.map({ $0 + SpeechStyle.steadyPaceHint }) else {
            return model.synthesize(text: text, voiceProfile: profile, language: language.rawValue, seed: seed)
        }
        return model.synthesize(
            text: text, voiceProfile: profile, language: language.rawValue, instruction: instruction, seed: seed)
    }

    /// The flow model was trained with a CAM++ speaker vector as its global timbre anchor.
    /// Without it, instruct2 (which hides the reference tokens from the LLM) lets an emotion
    /// pull the voice to someone else. A profile built before the speaker model was available
    /// is rebuilt once it is.
    private func profile(for sampleURL: URL, referenceText: String) async throws -> CosyVoiceVoiceProfile {
        let speaker = await SpeakerEmbedder.shared.reference(sampleURL)
        let key = sampleURL.path + "|" + referenceText + "|\(speaker != nil)"
        if let cachedProfile, cachedProfile.key == key { return cachedProfile.profile }
        let extracted = try model.extractVoiceProfile(
            audio: MonoAudioLoader.load(sampleURL, sampleRate: 24_000),
            sampleRate: 24_000,
            speechTokenizer: speechTokenizer,
            referenceTranscript: referenceText
        )
        let profile = CosyVoiceVoiceProfile(
            speakerEmbedding: speaker,
            promptToken: extracted.promptToken,
            promptFeat: extracted.promptFeat,
            promptText: extracted.promptText
        )
        cachedProfile = (key, profile)
        return profile
    }
}
