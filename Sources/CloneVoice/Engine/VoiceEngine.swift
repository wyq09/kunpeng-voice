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
    private var polishedParagraphs: [String: [String]] = [:]

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

    /// Returns mono float samples, their sample rate, and a notice when smart phrasing was skipped.
    /// `text` may contain inline tags like `[生气]`; each tagged part is spoken in its own style.
    /// `onProgress(0, 0)` means the script is still being phrased.
    func synthesize(
        text: String,
        sampleURL: URL,
        referenceText: String,
        language: VoiceLanguage,
        style: SpeechStyle = .natural,
        speed: SpeechSpeed = .normal,
        onProgress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> (samples: [Float], sampleRate: Int, notice: String?) {
        guard let spec = loadedSpec else { throw EngineError.notReady }
        let usesInstruction = spec.supportsEmotionInstruction
        let (jobs, notice) = try await phrase(text, style: style, maxLength: spec.chunkLength, onProgress: onProgress)
        guard !jobs.isEmpty else { throw EngineError.emptyText }

        var output: [Float] = []
        var sampleRate = 24_000
        var previous: (chunk: SpokenChunk, style: SpeechStyle)?
        for (index, job) in jobs.enumerated() {
            try Task.checkCancellation()
            onProgress(index + 1, jobs.count)
            let result = try await worker.generateMatchingVoice(
                text: job.text,
                sampleURL: sampleURL,
                referenceText: referenceText,
                language: language,
                style: job.style,
                previous: previous?.style == job.style ? previous?.chunk : nil
            )
            sampleRate = result.sampleRate
            previous = (SpokenChunk(samples: result.samples, text: job.text), job.style)
            let prosody = job.style.prosody
            let followedInstruction = usesInstruction && !result.isFaithfulFallback
            output += try AudioEffects.process(
                result.samples,
                sampleRate: sampleRate,
                rate: (followedInstruction ? 1 : prosody.tempo) * speed.rate,
                pitchCents: followedInstruction ? 0 : prosody.pitchCents
            )
            if index < jobs.count - 1 {
                let pause = job.boundary.pause(base: prosody.pause) / Double(speed.rate)
                output += [Float](repeating: 0, count: Int(Double(sampleRate) * pause))
            }
        }
        return (AudioEffects.normalized(output), sampleRate, notice)
    }

    private struct Job {
        let style: SpeechStyle
        let text: String
        let boundary: TextChunker.Boundary
    }

    /// Splits the script into spoken phrases, asking the configured language model for natural
    /// breaks when available and falling back to punctuation rules per paragraph.
    private func phrase(
        _ text: String, style: SpeechStyle, maxLength: Int, onProgress: @MainActor (Int, Int) -> Void
    ) async throws -> (jobs: [Job], notice: String?) {
        let segments = StyledScript(text, defaultStyle: style).segments.map {
            (style: $0.style, paragraphs: TextChunker.paragraphs($0.text))
        }
        let config = PolisherConfig.load()
        var notice: String?
        if config.isUsable {
            onProgress(0, 0)
            let pending = Set(segments.flatMap(\.paragraphs)).filter {
                polishedParagraphs[cacheKey($0, maxLength, config)] == nil
            }
            let results = await withTaskGroup(of: (String, Result<[String], Error>).self) { group in
                for paragraph in pending {
                    group.addTask { await Self.polish(paragraph, maxLength: maxLength, config: config) }
                }
                return await group.reduce(into: []) { $0.append($1) }
            }
            try Task.checkCancellation()
            for (paragraph, result) in results {
                switch result {
                case .success(let lines): polishedParagraphs[cacheKey(paragraph, maxLength, config)] = lines
                case .failure(let error): notice = "智能断句没成功（\(error.localizedDescription)），已按标点断句"
                }
            }
        }

        var jobs: [Job] = []
        for segment in segments {
            for paragraph in segment.paragraphs {
                // The model contributes punctuation; packing by that punctuation keeps chunk sizes even.
                let punctuated = config.isUsable ? polishedParagraphs[cacheKey(paragraph, maxLength, config)]?.joined() : nil
                let phrases = TextChunker.split(punctuated ?? paragraph, maxLength: maxLength)
                for (index, phrase) in phrases.enumerated() {
                    let boundary = index == phrases.count - 1 ? .paragraph : TextChunker.Boundary(after: phrase)
                    jobs.append(Job(style: segment.style, text: phrase, boundary: boundary))
                }
            }
        }
        return (jobs, notice)
    }

    /// Kept out of the `addTask` closure: inlined there, Swift 6.4 -O registers the children with no
    /// group, which then returns empty and crashes when their results arrive.
    nonisolated private static func polish(
        _ paragraph: String, maxLength: Int, config: PolisherConfig
    ) async -> (String, Result<[String], Error>) {
        do { return (paragraph, .success(try await ScriptPolisher.lines(for: paragraph, maxLength: maxLength, config: config))) }
        catch { return (paragraph, .failure(error)) }
    }

    private func cacheKey(_ paragraph: String, _ maxLength: Int, _ config: PolisherConfig) -> String {
        "\(config.baseURL)|\(config.model)|\(config.prompt)|\(maxLength)|\(paragraph)"
    }
}

protocol CloneBackend: AnyObject {
    var sampleRate: Int { get }
    /// `faithful` trades style control for voice fidelity: style instructions can pull the
    /// model away from the reference speaker, so retries after a voice drift drop them.
    /// `previous` is the chunk spoken just before in the same style, for backends that can continue from it.
    func generate(
        text: String, sampleURL: URL, referenceText: String, language: VoiceLanguage, style: SpeechStyle,
        faithful: Bool, previous: SpokenChunk?
    ) async throws -> [Float]
}

/// Raw model output for one chunk, at the backend's sample rate.
struct SpokenChunk {
    let samples: [Float]
    let text: String
}

/// Owns the non-Sendable model so it is only ever touched from one executor.
actor SynthesisWorker {
    /// Beyond this a chunk no longer sounds like the same person (male ≈ 100 Hz, female ≈ 200 Hz).
    private static let maxPitchDrift: Float = 4
    /// Speaking this much faster or slower than the reference sounds rushed or dragged.
    private static let maxRateRatio: Double = 1.45
    private static let faithfulRetries = 2

    private var backend: CloneBackend?
    private var reference: (url: URL, text: String, profile: SpeakerProfile?)?

    private struct SpeakerProfile {
        let pitch: Float?
        let syllablesPerSecond: Double?
    }

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

    /// Generates a chunk and regenerates it in faithful mode if its pitch or pace strays from the
    /// reference speaker, keeping whichever take sounds closest to the cloned voice.
    func generateMatchingVoice(
        text: String,
        sampleURL: URL,
        referenceText: String,
        language: VoiceLanguage,
        style: SpeechStyle,
        previous: SpokenChunk?
    ) async throws -> (samples: [Float], sampleRate: Int, isFaithfulFallback: Bool) {
        guard let backend else { throw EngineError.notReady }
        let rate = backend.sampleRate
        func take(faithful: Bool) async throws -> [Float] {
            let samples = try await backend.generate(
                text: text, sampleURL: sampleURL, referenceText: referenceText,
                language: language, style: style, faithful: faithful, previous: previous)
            releaseGPUMemory()
            return samples
        }

        let profile = speakerProfile(sampleURL, referenceText)
        let syllables = VoicePitch.syllables(in: text)
        /// 0 is a perfect match; above 1 the take no longer sounds like the reference.
        func mismatch(_ samples: [Float]) -> Double {
            var score = 0.0
            if let pitch = profile.pitch, let heard = VoicePitch.median(of: samples, sampleRate: rate) {
                score = Double(VoicePitch.semitones(heard, from: pitch) / Self.maxPitchDrift)
            }
            if syllables >= 8, let expected = profile.syllablesPerSecond,
               let seconds = VoicePitch.speakingSeconds(of: samples, sampleRate: rate), seconds > 0 {
                score = max(score, abs(log(syllables / seconds / expected)) / log(Self.maxRateRatio))
            }
            return score
        }

        var best = (samples: try await take(faithful: false), isFaithfulFallback: false)
        var bestScore = mismatch(best.samples)
        for _ in 0..<Self.faithfulRetries where bestScore > 1 {
            try Task.checkCancellation()
            let candidate = try await take(faithful: true)
            let score = mismatch(candidate)
            if score < bestScore { (best, bestScore) = ((candidate, true), score) }
        }
        return (best.samples, rate, best.isFaithfulFallback)
    }

    private func speakerProfile(_ url: URL, _ text: String) -> SpeakerProfile {
        if let reference, reference.url == url, reference.text == text, let profile = reference.profile { return profile }
        let samples = try? MonoAudioLoader.load(url, sampleRate: 24_000)
        let seconds = samples.flatMap { VoicePitch.speakingSeconds(of: $0, sampleRate: 24_000) }
        let syllables = VoicePitch.syllables(in: text)
        let profile = SpeakerProfile(
            pitch: samples.flatMap { VoicePitch.median(of: $0, sampleRate: 24_000) },
            syllablesPerSecond: seconds.flatMap { $0 > 1 && syllables >= 8 ? syllables / $0 : nil }
        )
        reference = (url, text, profile)
        return profile
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
    /// How a phrase ends decides how long the silence after it is.
    enum Boundary {
        case clause, sentence, paragraph

        init(after phrase: String) {
            let ending = phrase.last { !TextChunker.closers.contains($0) }
            self = ending.map { TextChunker.sentenceEnds.contains($0) } == true ? .sentence : .clause
        }

        func pause(base: Double) -> Double {
            switch self {
            case .clause: base * 0.5
            case .sentence: base
            case .paragraph: max(base * 2, 0.5)
            }
        }
    }

    fileprivate static let sentenceEnds: Set<Character> = ["。", "！", "？", "；", "!", "?", ";", "…", "."]
    private static let clauseEnds: Set<Character> = ["，", "、", "：", ",", ":", "—"]
    fileprivate static let closers: Set<Character> = ["”", "’", "」", "』", "）", ")", "\"", "》"]

    static func paragraphs(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Packs whole sentences into chunks of at most `maxLength`; sentences that are too long on
    /// their own are broken at commas, so a chunk never ends in the middle of a phrase.
    static func split(_ text: String, maxLength: Int = 120) -> [String] {
        let sentences = pieces(of: text, endingWith: sentenceEnds).flatMap { sentence in
            sentence.count > maxLength ? pack(pieces(of: sentence, endingWith: clauseEnds), maxLength: maxLength) : [sentence]
        }
        return pack(sentences, maxLength: maxLength)
    }

    private static func pieces(of text: String, endingWith marks: Set<Character>) -> [String] {
        var pieces: [String] = []
        var current = ""
        var isBreakPending = false
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            current.append(character)
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            // "3.5" and "App.Store" are not sentence ends.
            if marks.contains(character), character != "." || next == nil || next == " " { isBreakPending = true }
            // Keep "。”" and "？！" together with the phrase they close.
            if isBreakPending, !(next.map { marks.contains($0) || closers.contains($0) } ?? false) {
                pieces.append(current)
                current = ""
                isBreakPending = false
            }
        }
        pieces.append(current)
        return pieces.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func pack(_ parts: [String], maxLength: Int) -> [String] {
        var chunks: [String] = []
        var buffer = ""
        for part in parts {
            if !buffer.isEmpty, buffer.count + part.count > maxLength {
                chunks.append(buffer)
                buffer = ""
            }
            buffer += buffer.last?.isASCII == true && part.first?.isASCII == true ? " " + part : part
        }
        if !buffer.isEmpty { chunks.append(buffer) }
        return chunks.flatMap { $0.count > maxLength * 2 ? hardWrap($0, maxLength) : [$0] }
    }

    /// Last resort for runs without any punctuation.
    private static func hardWrap(_ text: String, _ maxLength: Int) -> [String] {
        stride(from: 0, to: text.count, by: maxLength).map { start in
            let from = text.index(text.startIndex, offsetBy: start)
            let to = text.index(from, offsetBy: min(maxLength, text.count - start))
            return String(text[from..<to])
        }
    }
}
