import Foundation

struct Voice: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    let duration: TimeInterval
    /// Transcript of the reference clip; the model needs it to align voice and text.
    let referenceText: String
    let sampleFileName: String
    var clips: [Clip] = []

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
        return speed == .normal ? style.title : "\(style.title) · \(speed.title)速"
    }
}
