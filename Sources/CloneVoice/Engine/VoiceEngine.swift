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
        var previous: SpokenChunk?
        /// Last measured pace per style, for chunks too short to measure on their own.
        var lastPace: [SpeechStyle: Double] = [:]
        for (index, job) in jobs.enumerated() {
            try Task.checkCancellation()
            onProgress(index + 1, jobs.count)
            let result = try await worker.generateMatchingVoice(
                text: job.text,
                sampleURL: sampleURL,
                referenceText: referenceText,
                language: language,
                style: job.style,
                followsInstructions: usesInstruction,
                previous: previous
            )
            sampleRate = result.sampleRate
            let prosody = job.style.prosody
            let followedInstruction = usesInstruction && !result.isFaithfulFallback
            if let pace = result.pace { lastPace[job.style] = pace }
            // A model that acted the instruction out should already speak at the style's tempo;
            // otherwise it speaks like the reference and the style tempo is added by stretching.
            // Short chunks borrow the last pace measured in their style.
            let expectedPace = followedInstruction ? prosody.tempo : 1
            let drift = (result.pace ?? lastPace[job.style]).map {
                PaceControl.driftCorrection(measuredPace: $0, expected: expectedPace)
            } ?? 1
            let correction = drift * (followedInstruction ? 1 : prosody.tempo)
            let pitchCents = followedInstruction ? 0 : prosody.appliedPitchCents
            let rate = PaceControl.rate(correction: correction, speed: speed)
            let processed = try AudioEffects.process(result.samples, sampleRate: sampleRate, rate: rate, pitchCents: pitchCents)
            output += processed
            PaceControl.debugLog(
                "[\(job.style.title)] pace=\(result.pace.map { String(format: "%.2f", $0) } ?? "–") "
                    + "expected=\(String(format: "%.2f", expectedPace)) rate=\(String(format: "%.2f", rate))"
                    + "\(result.isFaithfulFallback ? " faithful" : "") 「\(job.text.prefix(12))」")
            // Continue from a take corrected to the style's pace so one rushed chunk can't make the
            // next copy and compound it. The user's speed is left out (it's applied again to every
            // chunk), and pitch-shifted audio would pull the timbre, so that is never used.
            let paced = pitchCents == 0 && speed == .normal
                ? processed
                : try AudioEffects.process(result.samples, sampleRate: sampleRate, rate: correction, pitchCents: 0)
            previous = SpokenChunk(samples: paced, text: job.text, style: job.style)
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

/// Keeps every chunk at the pace its style calls for. Each chunk is generated on its own and
/// autoregressive models drift in speed from take to take, which is what makes a tagged script
/// suddenly rush or drag; the fix is to measure each take and time-stretch it to a target.
enum PaceControl {
    /// Takes already this close to the target are left untouched, so the stretch never adds
    /// artifacts for nothing and natural variation survives.
    static let tolerance = 1.08
    /// Total stretch never goes beyond this; more audibly warbles the voice.
    static let rateRange: ClosedRange<Float> = 0.75...1.35

    /// Final playback rate: the pace correction, then the user's speed applied in full.
    static func rate(correction: Float, speed: SpeechSpeed) -> Float {
        clamped(correction * speed.rate)
    }

    /// Stretch that brings a take whose pace is `measuredPace` times the reference speaker's to
    /// the pace the model was expected to produce. Only the drift beyond the tolerance is
    /// corrected, keeping the mapping smooth.
    static func driftCorrection(measuredPace: Double, expected: Float) -> Float {
        guard measuredPace > 0, expected > 0 else { return 1 }
        let deviation = log(measuredPace / Double(expected))
        let excess = max(0, abs(deviation) - log(tolerance)) * (deviation < 0 ? -1 : 1)
        return clamped(Float(exp(-excess)))
    }

    private static func clamped(_ rate: Float) -> Float {
        min(max(rate, rateRange.lowerBound), rateRange.upperBound)
    }

    /// Per-chunk pace report on stderr, for tuning: `CLONEVOICE_DEBUG_PACE=1 CloneVoice speak …`.
    static func debugLog(_ message: @autoclosure () -> String) {
        guard ProcessInfo.processInfo.environment["CLONEVOICE_DEBUG_PACE"] != nil else { return }
        FileHandle.standardError.write(Data((message() + "\n").utf8))
    }
}

protocol CloneBackend: AnyObject {
    var sampleRate: Int { get }
    /// `faithful` trades style control for voice fidelity: style instructions can pull the
    /// model away from the reference speaker, so retries after a voice drift drop them.
    /// `previous` is the chunk spoken just before, for backends that can continue from it.
    /// `variant` changes the sampling seed so a retry doesn't reproduce the same take.
    func generate(
        text: String, sampleURL: URL, referenceText: String, language: VoiceLanguage, style: SpeechStyle,
        faithful: Bool, previous: SpokenChunk?, variant: Int
    ) async throws -> [Float]
}

/// Raw model output for one chunk, at the backend's sample rate.
struct SpokenChunk {
    let samples: [Float]
    let text: String
    let style: SpeechStyle
}

/// Owns the non-Sendable model so it is only ever touched from one executor.
actor SynthesisWorker {
    /// Semitones from the expected pitch beyond which a chunk no longer sounds like the same
    /// person (male ≈ 100 Hz, female ≈ 200 Hz). Acted emotions are measured around the style's
    /// expected shift; whether the timbre held is the speaker similarity's call.
    private static let maxPitchDrift: Float = 4
    /// A take whose speaker similarity sits this far below the voice's usual level sounds like
    /// someone else. Acting an emotion out lowers it by itself, by 0.15–0.2 in a well-anchored
    /// take, so a tighter margin would reject every emotion.
    private static let timbreMargin: Float = 0.2
    /// Usual similarity assumed until the voice has plain takes of its own on this model
    /// (plain takes measured 0.68 on Qwen3, 0.84 on CosyVoice 3, 0.88 on VoxCPM 2).
    private static let defaultTimbreBaseline: Float = 0.7
    /// Plain takes kept per voice to set its usual similarity.
    private static let baselineSamples = 16
    /// Pace is corrected afterwards, so only a take this far off counts as broken: at that point
    /// the model has usually skipped or repeated words rather than just spoken fast.
    private static let brokenPaceRatio: Double = 1.8
    private static let retries = 2
    /// Fewer syllables than this can't be timed reliably.
    private static let minSyllablesForPace = 8.0

    private var backend: CloneBackend?
    private var reference: (url: URL, text: String, profile: SpeakerProfile?)?
    /// Speaker similarity of takes spoken without an emotion, per voice sample. Each model
    /// clones a voice to a different degree, so this starts over when the model changes.
    private var plainSimilarities: [String: [Float]] = [:]

    private struct SpeakerProfile {
        let pitch: Float?
        let syllablesPerSecond: Double?
    }

    func load(_ spec: ModelSpec, from directory: URL) async throws {
        SpeakerEmbedder.prepare()
        backend = nil
        plainSimilarities = [:]
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

    /// Generates a chunk and retries when it strays. A low speaker similarity or a pitch drift
    /// means the voice stopped sounding like the speaker: an acted emotion gets one reroll with
    /// a new seed first, and only then is the style dropped for fidelity. Similarity is judged
    /// against what this voice usually reaches without an emotion, so voices that clone less
    /// closely aren't held to a fixed bar. A wildly wrong pace means garbled content, so that
    /// retry rerolls in the same mode. Plain fast or slow takes are not retried; the caller
    /// stretches them to pace, keeping the emotion intact.
    /// `pace` is the take's speaking rate relative to the reference, when measurable.
    func generateMatchingVoice(
        text: String,
        sampleURL: URL,
        referenceText: String,
        language: VoiceLanguage,
        style: SpeechStyle,
        followsInstructions: Bool,
        previous: SpokenChunk?
    ) async throws -> (samples: [Float], sampleRate: Int, isFaithfulFallback: Bool, pace: Double?) {
        guard let backend else { throw EngineError.notReady }
        let rate = backend.sampleRate
        var variant = 0
        func take(faithful: Bool) async throws -> [Float] {
            defer { variant += 1 }
            let samples = try await backend.generate(
                text: text, sampleURL: sampleURL, referenceText: referenceText,
                language: language, style: style, faithful: faithful, previous: previous, variant: variant)
            releaseGPUMemory()
            return samples
        }

        let profile = speakerProfile(sampleURL, referenceText)
        let syllables = VoicePitch.syllables(in: text)
        func pace(of samples: [Float]) -> Double? {
            guard syllables >= Self.minSyllablesForPace, let expected = profile.syllablesPerSecond,
                  let seconds = VoicePitch.speakingSeconds(of: samples, sampleRate: rate), seconds > 0
            else { return nil }
            return syllables / seconds / expected
        }
        /// Each part: 0 is a perfect match, above 1 the take is unusable.
        /// Semitones from the reference speaker's median pitch.
        func pitchShift(of samples: [Float]) -> Float? {
            guard let pitch = profile.pitch, let heard = VoicePitch.median(of: samples, sampleRate: rate) else { return nil }
            return 12 * log2(heard / pitch)
        }
        func pitchScore(_ shift: Float?, faithful: Bool) -> Double {
            guard let shift else { return 0 }
            // An emotion legitimately raises or lowers the voice when the model acts it out.
            let isActing = followsInstructions && !faithful && style.instruction != nil
            let expectedShift = isActing ? style.prosody.pitchCents / 100 : 0
            return Double(abs(shift - expectedShift) / Self.maxPitchDrift)
        }
        func paceScore(_ pace: Double?) -> Double {
            pace.map { abs(log($0)) / log(Self.brokenPaceRatio) } ?? 0
        }
        let identity = await SpeakerEmbedder.shared.reference(sampleURL)
        let usualSimilarity = usualSimilarity(of: sampleURL)
        func similarity(of samples: [Float]) async -> Float? {
            guard let identity, let heard = await SpeakerEmbedder.shared.embedding(of: samples, sampleRate: rate)
            else { return nil }
            return SpeakerEmbedder.similarity(identity, heard)
        }

        struct Take {
            let samples: [Float]
            let faithful: Bool
            let pace: Double?
            let similarity: Float?
            let pitch: Double
            let timbre: Double
            let paceScore: Double
            var voiceDrifted: Bool { pitch > 1 || timbre > 1 }
            var worst: Double { max(pitch, timbre, paceScore) }
        }
        func evaluate(_ samples: [Float], faithful: Bool) async -> Take {
            let measured = pace(of: samples)
            let heard = await similarity(of: samples)
            let shift = pitchShift(of: samples)
            let take = Take(
                samples: samples, faithful: faithful, pace: measured, similarity: heard,
                pitch: pitchScore(shift, faithful: faithful),
                timbre: heard.map { Double(max(0, usualSimilarity - $0) / Self.timbreMargin) } ?? 0,
                paceScore: paceScore(measured))
            PaceControl.debugLog(String(
                format: "  take%@: similarity %@ (usual %.2f), pitch %@ st; scores timbre %.2f, pitch %.2f, pace %.2f (above 1 = retry)",
                faithful ? " (faithful)" : "", heard.map { String(format: "%.2f", $0) } ?? "–", usualSimilarity,
                shift.map { String(format: "%+.1f", $0) } ?? "–", take.timbre, take.pitch, take.paceScore))
            return take
        }

        let isActed = followsInstructions && style.instruction != nil
        var best = await evaluate(try await take(faithful: false), faithful: false)
        for attempt in 0..<Self.retries {
            guard best.voiceDrifted || best.paceScore > 1 else { break }
            try Task.checkCancellation()
            let rerollsEmotion = best.voiceDrifted && isActed && attempt == 0
            let faithful = best.faithful || (best.voiceDrifted && !rerollsEmotion)
            let candidate = await evaluate(try await take(faithful: faithful), faithful: faithful)
            if candidate.worst < best.worst { best = candidate }
        }
        if let similarity = best.similarity, best.faithful || style.instruction == nil {
            let recorded = plainSimilarities[sampleURL.path, default: []] + [similarity]
            plainSimilarities[sampleURL.path] = Array(recorded.suffix(Self.baselineSamples))
        }
        return (best.samples, rate, best.faithful, best.pace)
    }

    /// Median similarity of this voice's plain takes on the loaded model.
    private func usualSimilarity(of sampleURL: URL) -> Float {
        guard let recorded = plainSimilarities[sampleURL.path]?.sorted(), !recorded.isEmpty else {
            return Self.defaultTimbreBaseline
        }
        return recorded[recorded.count / 2]
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
