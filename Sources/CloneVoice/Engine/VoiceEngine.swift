import Foundation
import HuggingFace
import MLX
import MLXAudioCore
import MLXAudioTTS
import Observation

/// UI-facing model state. All heavy work is delegated to `SynthesisWorker`.
@MainActor
@Observable
final class VoiceEngine {
    enum Phase: Equatable {
        case idle
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    static let modelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit"
    static let modelSizeText = "3.1 GB"

    private(set) var phase: Phase = .idle
    private let worker = SynthesisWorker()
    private var prepareTask: Task<Void, Never>?

    var isReady: Bool { phase == .ready }

    func prepare() {
        guard prepareTask == nil, phase != .ready else { return }
        prepareTask = Task {
            defer { prepareTask = nil }
            do {
                try await worker.load(repo: Self.modelRepo) { fraction in
                    self.phase = fraction < 1 ? .downloading(fraction) : .loading
                }
                phase = .ready
            } catch {
                phase = .failed(Self.describe(error))
            }
        }
    }

    /// Returns mono float samples and their sample rate.
    func synthesize(
        text: String,
        sampleURL: URL,
        referenceText: String,
        style: SpeechStyle = .natural,
        speed: SpeechSpeed = .normal,
        onProgress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> (samples: [Float], sampleRate: Int) {
        let chunks = TextChunker.split(text)
        var output: [Float] = []
        var sampleRate = 24_000
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            onProgress(index + 1, chunks.count)
            let result = try await worker.generate(
                text: chunk,
                sampleURL: sampleURL,
                referenceText: referenceText,
                temperature: style.temperature
            )
            sampleRate = result.sampleRate
            if !output.isEmpty {
                output += [Float](repeating: 0, count: Int(Double(sampleRate) * style.pause))
            }
            output += result.samples
        }
        let processed = try AudioEffects.process(
            output,
            sampleRate: sampleRate,
            rate: style.tempo * speed.rate,
            pitchCents: style.pitchCents
        )
        return (processed, sampleRate)
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "网络不通，模型没下载完。检查网络后点重试。"
        }
        return error.localizedDescription
    }
}

/// Owns the non-Sendable model so it is only ever touched from one executor.
actor SynthesisWorker {
    private var model: SpeechGenerationModel?

    private static let mirrorHost = URL(string: "https://hf-mirror.com")!

    func load(repo: String, onProgress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        guard model == nil else { return }
        let repoID = Repo.ID(rawValue: repo)!
        let handler: @MainActor @Sendable (Progress) -> Void = { onProgress($0.fractionCompleted) }

        // Fixed location so the model is independent of the user's HF_HOME and stored only once.
        let cache = HubCache(cacheDirectory: Self.modelsRoot)
        let modelDir = Self.modelsRoot
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent(repo.replacingOccurrences(of: "/", with: "_"))
        let marker = modelDir.appendingPathComponent(".complete")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: modelDir.path), !fileManager.fileExists(atPath: marker.path) {
            try? fileManager.removeItem(at: modelDir)
        }

        do {
            _ = try await ModelUtils.resolveOrDownloadModel(
                client: HubClient(cache: cache),
                cache: cache,
                repoID: repoID,
                requiredExtension: "safetensors",
                progressHandler: handler
            )
        } catch {
            try? fileManager.removeItem(at: modelDir)
            _ = try await ModelUtils.resolveOrDownloadModel(
                client: HubClient(host: Self.mirrorHost, cache: cache),
                cache: cache,
                repoID: repoID,
                requiredExtension: "safetensors",
                progressHandler: handler
            )
        }
        fileManager.createFile(atPath: marker.path, contents: nil)
        await onProgress(1)
        let loaded = try await Qwen3TTSModel.fromModelDirectory(modelDir)
        // First inference JIT-compiles GPU kernels; pay that cost while the UI still says "loading".
        _ = try? await loaded.generate(text: "你好。", voice: nil, refAudio: nil, refText: nil, language: "chinese")
        Memory.clearCache()
        model = loaded
    }

    private static var modelsRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloneVoice/Models", isDirectory: true)
    }

    func generate(
        text: String,
        sampleURL: URL,
        referenceText: String,
        temperature: Float
    ) async throws -> (samples: [Float], sampleRate: Int) {
        guard let model else { throw EngineError.notReady }
        let (_, refAudio) = try loadAudioArray(from: sampleURL, sampleRate: model.sampleRate)
        var parameters = model.defaultGenerationParameters
        parameters.temperature = temperature
        let audio = try await model.generate(
            text: text,
            voice: nil,
            refAudio: refAudio,
            refText: referenceText,
            language: TextChunker.language(of: text),
            generationParameters: parameters
        )
        let samples = audio.asArray(Float.self)
        Memory.clearCache()
        return (samples, model.sampleRate)
    }
}

enum EngineError: LocalizedError {
    case notReady

    var errorDescription: String? { "模型还在准备，稍等片刻再试。" }
}

enum TextChunker {
    static let maxLength = 120

    /// Splits long text at sentence boundaries; the model stays more stable on short inputs.
    static func split(_ text: String) -> [String] {
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

    static func language(of text: String) -> String {
        let scalars = text.unicodeScalars
        if scalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) { return "japanese" }
        if scalars.contains(where: { (0xAC00...0xD7AF).contains($0.value) }) { return "korean" }
        if scalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) { return "chinese" }
        return "auto"
    }
}
