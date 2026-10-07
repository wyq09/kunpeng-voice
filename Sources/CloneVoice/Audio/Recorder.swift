import AVFoundation
import Observation

@MainActor
@Observable
final class Recorder {
    static let targetDuration: TimeInterval = 10
    static let maxDuration: TimeInterval = 20
    static let minDuration: TimeInterval = 3

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// 0...1, smoothed input loudness for the live meter.
    private(set) var level: Double = 0
    private(set) var isPermissionDenied = false

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var fileURL: URL?

    func start() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            isPermissionDenied = true
            return
        }
        isPermissionDenied = false

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 24_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else { return }
            self.recorder = recorder
            fileURL = url
            elapsed = 0
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } catch {
            isRecording = false
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        level = 0
    }

    func discard() {
        stop()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
        elapsed = 0
    }

    private func tick() {
        guard let recorder else { return }
        elapsed = recorder.currentTime
        recorder.updateMeters()
        let power = Double(recorder.averagePower(forChannel: 0))
        let normalized = max(0, min(1, (power + 50) / 50))
        level = level * 0.6 + normalized * 0.4
        if elapsed >= Self.maxDuration { stop() }
    }
}
