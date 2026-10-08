import Foundation

/// The language a voice should always be read in. Raw values are Qwen3-TTS language codes.
enum VoiceLanguage: String, CaseIterable, Identifiable, Codable {
    case chinese, english, japanese, korean, french, german, spanish, italian, portuguese, russian

    var id: Self { self }

    var title: String {
        switch self {
        case .chinese: "中文"
        case .english: "英语"
        case .japanese: "日语"
        case .korean: "韩语"
        case .french: "法语"
        case .german: "德语"
        case .spanish: "西班牙语"
        case .italian: "意大利语"
        case .portuguese: "葡萄牙语"
        case .russian: "俄语"
        }
    }

    /// Best guess from a transcript; Chinese when the text gives no clue.
    static func detect(in text: String) -> VoiceLanguage {
        let scalars = text.unicodeScalars
        if scalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) { return .japanese }
        if scalars.contains(where: { (0xAC00...0xD7AF).contains($0.value) }) { return .korean }
        if scalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) { return .chinese }
        if scalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) { return .russian }
        if scalars.contains(where: { CharacterSet.letters.contains($0) }) { return .english }
        return .chinese
    }
}
