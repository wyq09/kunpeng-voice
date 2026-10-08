import Foundation
import MLXAudioCore
import Observation

/// Owns in-app generations so they keep running while the user looks at other voices.
@MainActor
@Observable
final class Generator {
    struct Active {
        let startedAt: Date
        var current = 1
        var total = 1
        var isPhrasing: Bool { current == 0 }
    }

    private(set) var active: [Voice.ID: Active] = [:]
    /// Last outcome worth telling the user about, per voice.
    var messages: [Voice.ID: String] = [:]
    /// Unsent text per voice, so leaving a voice doesn't lose what was typed.
    var drafts: [Voice.ID: String] = [:]
    /// The voice on screen; finished clips only auto-play there.
    var visibleVoiceID: Voice.ID?

    private var tasks: [Voice.ID: Task<Void, Never>] = [:]

    func isGenerating(_ voiceID: Voice.ID) -> Bool { active[voiceID] != nil }

    func start(
        _ text: String,
        for voice: Voice,
        style: SpeechStyle,
        speed: SpeechSpeed,
        store: VoiceStore,
        engine: VoiceEngine,
        player: Player
    ) {
        let voiceID = voice.id
        guard tasks[voiceID] == nil else { return }
        let modelName = engine.loadedSpec?.name ?? "未知模型"
        let started = Date.now
        messages[voiceID] = nil
        active[voiceID] = Active(startedAt: started)

        tasks[voiceID] = Task {
            let recorder = JobRecorder(source: .app, voiceName: voice.name, modelName: modelName, text: text)
            recorder.modelReady(modelName)
            defer {
                tasks[voiceID] = nil
                active[voiceID] = nil
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
                    self.active[voiceID]?.current = current
                    self.active[voiceID]?.total = total
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
    }

    func cancel(_ voiceID: Voice.ID) {
        tasks[voiceID]?.cancel()
    }
}
