import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class VoiceStore {
    private(set) var voices: [Voice] = []

    let rootURL: URL
    private var indexURL: URL { rootURL.appendingPathComponent("voices.json") }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        rootURL = support.appendingPathComponent("CloneVoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        load()
    }

    func fileURL(_ name: String) -> URL { rootURL.appendingPathComponent(name) }

    func voice(id: Voice.ID?) -> Voice? { voices.first { $0.id == id } }

    /// Copies the sample into the library so the original file can be moved or deleted.
    func addVoice(name: String, sampleURL: URL, referenceText: String) throws -> Voice {
        let id = UUID()
        let fileName = "\(id.uuidString).\(sampleURL.pathExtension.isEmpty ? "wav" : sampleURL.pathExtension)"
        try FileManager.default.copyItem(at: sampleURL, to: fileURL(fileName))

        let voice = Voice(
            id: id,
            name: name,
            createdAt: .now,
            duration: Self.duration(of: fileURL(fileName)),
            referenceText: referenceText,
            sampleFileName: fileName
        )
        voices.insert(voice, at: 0)
        save()
        return voice
    }

    func rename(_ id: Voice.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = voices.firstIndex(where: { $0.id == id }) else { return }
        voices[index].name = trimmed
        save()
    }

    func setReferenceText(_ id: Voice.ID, to text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = voices.firstIndex(where: { $0.id == id }) else { return }
        voices[index].referenceText = trimmed
        save()
    }

    func setLanguage(_ id: Voice.ID, to language: VoiceLanguage) {
        guard let index = voices.firstIndex(where: { $0.id == id }) else { return }
        voices[index].language = language
        save()
    }

    func delete(_ id: Voice.ID) {
        guard let index = voices.firstIndex(where: { $0.id == id }) else { return }
        let voice = voices.remove(at: index)
        ([voice.sampleFileName] + voice.clips.map(\.fileName)).forEach {
            try? FileManager.default.removeItem(at: fileURL($0))
        }
        save()
    }

    func addClip(
        to voiceID: Voice.ID,
        text: String,
        fileName: String,
        style: SpeechStyle,
        speed: SpeechSpeed
    ) -> Clip? {
        guard let index = voices.firstIndex(where: { $0.id == voiceID }) else { return nil }
        let clip = Clip(
            id: UUID(),
            text: text,
            createdAt: .now,
            duration: Self.duration(of: fileURL(fileName)),
            fileName: fileName,
            style: style,
            speed: speed
        )
        voices[index].clips.insert(clip, at: 0)
        save()
        return clip
    }

    func deleteClip(_ clipID: Clip.ID, from voiceID: Voice.ID) {
        guard let index = voices.firstIndex(where: { $0.id == voiceID }),
              let clipIndex = voices[index].clips.firstIndex(where: { $0.id == clipID })
        else { return }
        let clip = voices[index].clips.remove(at: clipIndex)
        try? FileManager.default.removeItem(at: fileURL(clip.fileName))
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        voices = (try? JSONDecoder().decode([Voice].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(voices) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
