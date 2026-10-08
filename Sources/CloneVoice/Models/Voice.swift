import Foundation

struct Voice: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    let duration: TimeInterval
    /// Transcript of the reference clip; the model needs it to align voice and text.
    var referenceText: String
    let sampleFileName: String
    var clips: [Clip] = []
    /// Chosen by the user; otherwise inferred from the reference transcript.
    var language: VoiceLanguage?

    var primaryLanguage: VoiceLanguage { language ?? .detect(in: referenceText) }

    var subtitle: String {
        "\(createdAt.formatted(.dateTime.month().day())) · \(Int(duration.rounded())) 秒"
    }
}

struct Clip: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let createdAt: Date
    let duration: TimeInterval
    let fileName: String
    var style: SpeechStyle?
    var speed: SpeechSpeed?

    var deliveryText: String? {
        guard let style, let speed else { return nil }
        let styleText = StyledScript(text, defaultStyle: style).usesTags ? "多段情绪" : style.title
        return speed == .normal ? styleText : "\(styleText) · \(speed.title)速"
    }
}
