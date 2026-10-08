import Foundation
import MLXAudioCore

/// Synthesis without UI, shared by the command line and the MCP server.
@MainActor
final class HeadlessSpeaker {
    struct Result {
        let url: URL
        let duration: TimeInterval
        let voiceName: String
        let modelName: String
    }

    enum Failure: LocalizedError {
        case noVoices
        case unknownVoice(String, available: [String])
        case unknownStyle(String)
        case noModel
        case modelFailed(String)

        var errorDescription: String? {
            switch self {
            case .noVoices:
                "还没有声音。先打开「鲲鹏有声」应用录一段声音。"
            case .unknownVoice(let name, let available):
                "找不到声音「\(name)」。可用的声音：\(available.joined(separator: "、"))"
            case .unknownStyle(let name):
                "不认识情绪「\(name)」。可用：\(SpeechStyle.allCases.map(\.title).joined(separator: "、"))"
            case .noModel:
                "还没有下载模型。打开「鲲鹏有声」应用，在「模型管理」里下载一个模型后再试。"
            case .modelFailed(let message):
                message
            }
        }
    }

    static let defaultOutputDirectory = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("鲲鹏有声", isDirectory: true)

    private let store = VoiceStore()
    private let models = ModelManager()
    private let engine = VoiceEngine()

    var voices: [Voice] { store.voices }

    func voice(named name: String?) throws -> Voice {
        guard let first = store.voices.first else { throw Failure.noVoices }
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return first }
        if let exact = store.voices.first(where: { $0.name == name }) { return exact }
        if let partial = store.voices.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) { return partial }
        throw Failure.unknownVoice(name, available: store.voices.map(\.name))
    }

    static func style(named name: String?) throws -> SpeechStyle {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return .natural }
        guard let style = StyledScript.style(named: name) else { throw Failure.unknownStyle(name) }
        return style
    }

    static func speed(named name: String?) -> SpeechSpeed {
        switch name?.lowercased() {
        case "slow", "慢": .slow
        case "fast", "快": .fast
        default: .normal
        }
    }

    func speak(
        text: String,
        voiceName: String? = nil,
        style: SpeechStyle = .natural,
        speed: SpeechSpeed = .normal,
        output: URL? = nil
    ) async throws -> Result {
        let voice = try voice(named: voiceName)
        try await ensureModelLoaded()

        let result = try await engine.synthesize(
            text: text,
            sampleURL: store.fileURL(voice.sampleFileName),
            referenceText: voice.referenceText,
            language: voice.primaryLanguage,
            style: style,
            speed: speed
        ) { _, _ in }

        let url = output ?? Self.defaultOutputURL(voice: voice.name, text: text)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        try AudioUtils.writeWavFile(samples: result.samples, sampleRate: result.sampleRate, fileURL: url)
        return Result(
            url: url,
            duration: Double(result.samples.count) / Double(result.sampleRate),
            voiceName: voice.name,
            modelName: engine.loadedSpec?.name ?? models.activeSpec.name
        )
    }

    private func ensureModelLoaded() async throws {
        if engine.isReady { return }
        let spec = models.isActiveDownloaded
            ? models.activeSpec
            : ModelCatalog.all.first { models.status(of: $0) == .downloaded }
        guard let spec else { throw Failure.noModel }
        engine.load(spec, from: models.directory(for: spec))
        while engine.phase == .loading || engine.phase == .idle {
            try await Task.sleep(for: .milliseconds(100))
        }
        if case .failed(let message) = engine.phase { throw Failure.modelFailed(message) }
    }

    private static func defaultOutputURL(voice: String, text: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: .now)
        let snippet = StyledScript(text, defaultStyle: .natural).segments.map(\.text).joined()
            .prefix(16)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
        return defaultOutputDirectory.appendingPathComponent("\(voice)-\(stamp)-\(snippet).wav")
    }
}
