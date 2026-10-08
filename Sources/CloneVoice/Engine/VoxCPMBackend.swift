import Foundation
import VoxCPM2TTS

/// Serves both VoxCPM 2 and VoxCPM 1.5; the checkpoint's config decides which architecture runs.
final class VoxCPMBackend: CloneBackend {
    private let model: VoxCPM2TTSModel
    private var cachedReference: (url: URL, samples: [Float])?

    var sampleRate: Int { model.outputSampleRate }
    private var isVersion1: Bool { model.args.isVoxCPM1 }

    init(directory: URL, modelID: String) async throws {
        model = try await VoxCPM2TTSModel.fromPretrained(
            modelId: modelID,
            cacheDir: directory,
            offlineMode: true,
            tokenizerDirectory: directory
        )
    }

    /// Without a style, prompt continuation clones most faithfully. With a style, VoxCPM2's
    /// "controllable cloning" keeps the timbre from the reference and follows the instruction.
    /// VoxCPM 1.5 has no instruction support, so it always continues the prompt.
    func generate(
        text: String, sampleURL: URL, referenceText: String, language _: VoiceLanguage, style: SpeechStyle,
        faithful: Bool
    ) async throws -> [Float] {
        let reference = try reference(for: sampleURL)
        if isVersion1 {
            return try await model.generateVoxCPM2(
                text: text,
                promptText: referenceText,
                promptAudio: reference,
                streamingPrefixLen: 3
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
        let samples = try MonoAudioLoader.load(url, sampleRate: Double(model.args.audioVAEConfig.sampleRate))
        cachedReference = (url, samples)
        return samples
    }
}
