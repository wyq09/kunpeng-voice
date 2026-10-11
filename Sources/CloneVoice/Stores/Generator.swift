import Foundation
import MLXAudioCore
import Observation

/// Owns in-app generations so they keep running while the user looks at other voices.
@MainActor
@Observable
final class Generator {
    struct Run: Identifiable {
        let id: UUID
        let voiceID: Voice.ID
        let text: String
        let startedAt: Date
        var current = 1
        var total = 1
        var isPhrasing: Bool { current == 0 }
    }

    private(set) var runs: [UUID: Run] = [:]
    /// Last outcome worth telling the user about, per voice.
    var messages: [Voice.ID: String] = [:]
    /// Unsent text per voice, so leaving a voice doesn't lose what was typed.
    var drafts: [Voice.ID: String] = [:]
    /// The voice on screen; finished clips only auto-play there.
    var visibleVoiceID: Voice.ID?

    private var tasks: [UUID: Task<Void, Never>] = [:]

    var activeRunCount: Int { runs.count }

    func runs(for voiceID: Voice.ID) -> [Run] {
        runs.values.filter { $0.voiceID == voiceID }.sorted { $0.startedAt > $1.startedAt }
    }

    func isGenerating(_ voiceID: Voice.ID) -> Bool {
        runs.values.contains { $0.voiceID == voiceID }
    }

    @discardableResult
    func start(
        _ text: String,
        for voice: Voice,
        style: SpeechStyle,
        speed: SpeechSpeed,
        store: VoiceStore,
        engine: VoiceEngine,
        player: Player
    ) -> UUID {
        let voiceID = voice.id
        let runID = UUID()
        let modelName = engine.loadedSpec?.name ?? "未知模型"
        let started = Date.now
        messages[voiceID] = nil
        runs[runID] = Run(id: runID, voiceID: voiceID, text: text, startedAt: started)

        tasks[runID] = Task {
            let recorder = JobRecorder(source: .app, voiceName: voice.name, modelName: modelName, text: text)
            recorder.modelReady(modelName)
            defer {
                tasks[runID] = nil
                runs[runID] = nil
            }
            do {
                let result = try await engine.synthesize(
                    text: text,
                    sampleURL: store.fileURL(voice.sampleFileName),
                    referenceText: voice.referenceText,
                    language: voice.primaryLanguage,
                    style: style,
                    speed: speed
                ) { current, total in
                    self.runs[runID]?.current = current
                    self.runs[runID]?.total = total
                    recorder.progress(current, total)
                }
                try Task.checkCancellation()

                let fileName = "\(UUID().uuidString).wav"
                let url = store.fileURL(fileName)
                try AudioUtils.writeWavFile(samples: result.samples, sampleRate: result.sampleRate, fileURL: url)
                recorder.finish(output: url, duration: Double(result.samples.count) / Double(result.sampleRate), notice: result.notice)
                messages[voiceID] = result.notice
                if store.addClip(
                    to: voiceID, text: text, fileName: fileName, style: style, speed: speed,
                    modelName: modelName, generationSeconds: Date.now.timeIntervalSince(started)
                ) != nil, visibleVoiceID == voiceID {
                    player.toggle(url)
                }
            } catch is CancellationError {
                recorder.fail(CancellationError())
            } catch let error as EngineError {
                recorder.fail(error)
                messages[voiceID] = error.errorDescription
            } catch {
                recorder.fail(error)
                messages[voiceID] = "生成失败，改短一点再试试"
            }
        }
        return runID
    }

    func cancel(_ runID: UUID) {
        tasks[runID]?.cancel()
    }

    func cancelAll(for voiceID: Voice.ID) {
        for run in runs(for: voiceID) {
            tasks[run.id]?.cancel()
        }
    }
}
