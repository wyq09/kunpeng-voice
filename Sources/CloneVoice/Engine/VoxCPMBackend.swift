import Foundation
import MLXRandom
import VoxCPM2TTS

/// Serves both VoxCPM 2 and VoxCPM 1.5; the checkpoint's config decides which architecture runs.
final class VoxCPMBackend: CloneBackend {
    /// One noise seed for every chunk of a script keeps the chunks sounding like one take.
    private static let seed: UInt64 = 20_260_806

    private let model: VoxCPM2TTSModel
    private var cachedReference: (url: URL, samples: [Float])?

    var sampleRate: Int { model.outputSampleRate }
    private var encoderRate: Int { model.args.audioVAEConfig.sampleRate }
    private var isVersion1: Bool { model.args.isVoxCPM1 }

    init(directory: URL, modelID: String) async throws {
        model = try await VoxCPM2TTSModel.fromPretrained(
            modelId: modelID,
            cacheDir: directory,
            offlineMode: true,
            tokenizerDirectory: directory
        )
    }

    /// VoxCPM2 keeps the reference as the timbre anchor and, for follow-up chunks, continues
    /// from the previous chunk so pace and tone carry over instead of restarting each time.
    /// Without a previous chunk: prompt continuation of the reference, or "controllable cloning"
    /// when a style is set. VoxCPM 1.5 has no separate timbre input, so it always continues the reference.
    func generate(
        text: String, sampleURL: URL, referenceText: String, language _: VoiceLanguage, style: SpeechStyle,
        faithful: Bool, previous: SpokenChunk?
    ) async throws -> [Float] {
        let reference = try reference(for: sampleURL)
        if !faithful { MLXRandom.seed(Self.seed) }
        if isVersion1 {
            return try await model.generateVoxCPM2(
                text: text,
                promptText: referenceText,
                promptAudio: reference,
                streamingPrefixLen: 3
            )
        }
        if !faithful, let previous {
            return try await model.generateVoxCPM2(
                text: text,
                refAudio: reference,
                promptText: previous.text,
                promptAudio: AudioEffects.resampled(previous.samples, from: sampleRate, to: encoderRate)
            )
        }
        guard !faithful, let instruction = style.styleDescription else {
            return try await model.generateVoxCPM2(
                text: text,
                refAudio: reference,
                promptText: referenceText,
                promptAudio: reference
            )
        }
        return try await model.generateVoxCPM2(text: text, refAudio: reference, instruct: instruction)
    }

    private func reference(for url: URL) throws -> [Float] {
        if let cachedReference, cachedReference.url == url { return cachedReference.samples }
        let samples = try MonoAudioLoader.load(url, sampleRate: Double(encoderRate))
        cachedReference = (url, samples)
        return samples
    }
}
