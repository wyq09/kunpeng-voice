import CosyVoiceTTS
import Foundation

/// Downloads (once) and runs the CAM++ speaker model: a 192-d voice identity vector that
/// anchors CosyVoice's timbre and tells whether a generated take still sounds like the
/// reference speaker. Weights live next to the denoiser, outside the TTS model folder.
actor SpeakerEmbedder {
    static let shared = SpeakerEmbedder()
    static let directory = Denoiser.directory.deletingLastPathComponent()
        .appendingPathComponent("CamPlusPlus-Speaker", isDirectory: true)
    private static let sampleRate = 16_000
    /// Shorter takes give an unreliable identity; they are not judged.
    private static let minSpeechSeconds = 1.5

    private var loading: Task<CamPlusPlusSpeaker, Error>?
    private var loaded: CamPlusPlusSpeaker?
    private var hasWaited = false
    private var references: [String: [Float]] = [:]

    /// Starts fetching the small model so it's ready by the time the first take is judged.
    nonisolated static func prepare() {
        Task.detached(priority: .utility) { await shared.startLoading() }
    }

    private func startLoading() { _ = loadTask() }

    /// Identity of a voice sample, cached per file. `nil` while the model isn't available:
    /// synthesis must never wait on this download for long.
    func reference(_ url: URL) async -> [Float]? {
        if let cached = references[url.path] { return cached }
        guard let samples = try? MonoAudioLoader.load(url, sampleRate: Double(Self.sampleRate)),
              let embedding = await embedding(of: samples, sampleRate: Self.sampleRate)
        else { return nil }
        references[url.path] = embedding
        return embedding
    }

    /// `nil` for takes with too little speech to judge, or when the model isn't available.
    func embedding(of samples: [Float], sampleRate: Int) async -> [Float]? {
        guard (VoicePitch.speakingSeconds(of: samples, sampleRate: sampleRate) ?? 0) >= Self.minSpeechSeconds,
              let model = await availableModel()
        else { return nil }
        return try? model.embed(audio: samples, sampleRate: sampleRate)
    }

    static func similarity(_ a: [Float], _ b: [Float]) -> Float {
        let dot = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let norms = sqrt(a.reduce(0) { $0 + $1 * $1 }) * sqrt(b.reduce(0) { $0 + $1 * $1 })
        return norms > 0 ? dot / norms : 0
    }

    /// A model already on disk is always waited for: its first load compiles for the Neural
    /// Engine and can take a while. The download is waited for once per session; after that a
    /// slow network only means takes go unjudged until it finishes in the background.
    private func availableModel() async -> CamPlusPlusSpeaker? {
        if let loaded { return loaded }
        let task = loadTask()
        if Self.isDownloaded {
            loaded = try? await task.value
            return loaded
        }
        guard !hasWaited else { return nil }
        hasWaited = true
        loaded = try? await Self.value(of: task, waitingAtMost: .seconds(20))
        return loaded
    }

    private static func value(
        of task: Task<CamPlusPlusSpeaker, Error>, waitingAtMost timeout: Duration
    ) async throws -> CamPlusPlusSpeaker {
        try await withThrowingTaskGroup(of: CamPlusPlusSpeaker?.self) { group in
            group.addTask { try await task.value }
            group.addTask { try await Task.sleep(for: timeout); return nil }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let model = first else { throw CancellationError() }
            return model
        }
    }

    private static var completeMarker: URL { directory.appendingPathComponent(".complete") }
    private static var isDownloaded: Bool { FileManager.default.fileExists(atPath: completeMarker.path) }

    private func loadTask() -> Task<CamPlusPlusSpeaker, Error> {
        if let loading { return loading }
        let task = Task<CamPlusPlusSpeaker, Error> {
            let directory = Self.directory
            if !Self.isDownloaded {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try await ResumableDownloader(
                    repo: CamPlusPlusSpeaker.defaultModelId,
                    patterns: ["CamPlusPlus.mlmodelc/*"],
                    destination: directory
                ) { _ in }.run()
                FileManager.default.createFile(atPath: Self.completeMarker.path, contents: nil)
            }
            return try CamPlusPlusSpeaker.load(from: directory)
        }
        loading = task
        Task { await self.settle(task) }
        return task
    }

    /// A finished download takes effect right away; a failed one doesn't stick, so the next
    /// take tries again.
    private func settle(_ task: Task<CamPlusPlusSpeaker, Error>) async {
        if let model = try? await task.value {
            loaded = model
        } else if loading == task {
            loading = nil
        }
    }
}
