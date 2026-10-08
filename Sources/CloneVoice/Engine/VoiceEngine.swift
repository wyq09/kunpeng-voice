import Foundation
import Observation

/// UI-facing state of the loaded model. All heavy work is delegated to `SynthesisWorker`.
@MainActor
@Observable
final class VoiceEngine {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var loadedSpec: ModelSpec?
    private let worker = SynthesisWorker()
    private var loadTask: Task<Void, Never>?

    var isReady: Bool { phase == .ready }

    func load(_ spec: ModelSpec, from directory: URL) {
        guard loadedSpec != spec || phase != .ready else { return }
        loadTask?.cancel()
        phase = .loading
        loadTask = Task {
            do {
                try await worker.load(spec, from: directory)
                guard !Task.isCancelled else { return }
                loadedSpec = spec
                phase = .ready
            } catch {
                guard !Task.isCancelled else { return }
                loadedSpec = nil
                phase = .failed("模型加载失败，可在模型管理里删除后重新下载。")
            }
        }
    }

    func unload() {
        loadTask?.cancel()
        loadedSpec = nil
        phase = .idle
        Task { await worker.unload() }
    }

    /// Returns mono float samples and their sample rate.
    /// `text` may contain inline tags like `[生气]`; each tagged part is spoken in its own style.
    func synthesize(
        text: String,
        sampleURL: URL,
        referenceText: String,
        language: VoiceLanguage,
        style: SpeechStyle = .natural,
        speed: SpeechSpeed = .normal,
        onProgress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> (samples: [Float], sampleRate: Int) {
        guard let spec = loadedSpec else { throw EngineError.notReady }
        let usesInstruction = spec.supportsEmotionInstruction
        let jobs = StyledScript(text, defaultStyle: style).segments.flatMap { segment in
            TextChunker.split(segment.text, maxLength: spec.chunkLength).map { (style: segment.style, text: $0) }
        }
        guard !jobs.isEmpty else { throw EngineError.emptyText }

        var output: [Float] = []
        var sampleRate = 24_000
        for (index, job) in jobs.enumerated() {
            try Task.checkCancellation()
            onProgress(index + 1, jobs.count)
            let result = try await worker.generate(
                text: job.text,
                sampleURL: sampleURL,
                referenceText: referenceText,
                language: language,
                style: job.style
            )
            sampleRate = result.sampleRate
            let prosody = job.style.prosody
            let shaped = try AudioEffects.process(
                result.samples,
                sampleRate: sampleRate,
                rate: (usesInstruction ? 1 : prosody.tempo) * speed.rate,
                pitchCents: usesInstruction ? 0 : prosody.pitchCents
            )
            if !output.isEmpty {
                output += [Float](repeating: 0, count: Int(Double(sampleRate) * prosody.pause))
            }
            output += shaped
        }
        return (AudioEffects.normalized(output), sampleRate)
    }
}

protocol CloneBackend: AnyObject {
    var sampleRate: Int { get }
    func generate(
        text: String, sampleURL: URL, referenceText: String, language: VoiceLanguage, style: SpeechStyle
    ) async throws -> [Float]
}

/// Owns the non-Sendable model so it is only ever touched from one executor.
actor SynthesisWorker {
    private var backend: CloneBackend?

    func load(_ spec: ModelSpec, from directory: URL) async throws {
        backend = nil
        releaseGPUMemory()
        switch spec.family {
        case .qwen3: backend = try await Qwen3Backend(directory: directory)
        case .cosyVoice: backend = try await CosyVoiceBackend(directory: directory, modelID: spec.id)
        case .voxCPM2, .voxCPM15: backend = try await VoxCPMBackend(directory: directory, modelID: spec.id)
        }
    }

    func unload() {
        backend = nil
        releaseGPUMemory()
    }

    func generate(
        text: String,
        sampleURL: URL,
        referenceText: String,
        language: VoiceLanguage,
        style: SpeechStyle
    ) async throws -> (samples: [Float], sampleRate: Int) {
        guard let backend else { throw EngineError.notReady }
        let samples = try await backend.generate(
            text: text, sampleURL: sampleURL, referenceText: referenceText, language: language, style: style)
        releaseGPUMemory()
        return (samples, backend.sampleRate)
    }
}

enum EngineError: LocalizedError {
    case notReady
    case emptyText

    var errorDescription: String? {
        switch self {
        case .notReady: "模型还在准备，稍等片刻再试。"
        case .emptyText: "去掉标签后没有可读的文字。"
        }
    }
}

enum TextChunker {
    /// Splits long text at sentence boundaries; the models stay more stable on short inputs.
    static func split(_ text: String, maxLength: Int = 120) -> [String] {
        let terminators: Set<Character> = ["。", "！", "？", "；", "!", "?", ";", "\n", "."]
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if terminators.contains(character) {
                sentences.append(current)
                current = ""
            }
        }
        sentences.append(current)

        var chunks: [String] = []
        var buffer = ""
        for sentence in sentences.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !sentence.isEmpty {
            if !buffer.isEmpty, buffer.count + sentence.count > maxLength {
                chunks.append(buffer)
                buffer = ""
            }
            buffer += buffer.isEmpty ? sentence : " " + sentence
        }
        if !buffer.isEmpty { chunks.append(buffer) }
        return chunks
    }
}
