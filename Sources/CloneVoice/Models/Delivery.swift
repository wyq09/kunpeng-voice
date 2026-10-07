import Foundation

/// The clone model ignores text instructions when conditioned on reference audio,
/// so each style is expressed through sampling and prosody (pitch, tempo, pauses).
enum SpeechStyle: String, CaseIterable, Identifiable, Codable {
    case natural, calm, happy, broadcast, story

    var id: Self { self }

    var title: String {
        switch self {
        case .natural: "自然"
        case .calm: "平静"
        case .happy: "开心"
        case .broadcast: "播音"
        case .story: "讲故事"
        }
    }

    var temperature: Float {
        switch self {
        case .natural: 0.9
        case .calm: 0.65
        case .happy: 1.0
        case .broadcast: 0.55
        case .story: 0.85
        }
    }

    var pitchCents: Float {
        switch self {
        case .natural, .broadcast: 0
        case .calm: -60
        case .happy: 150
        case .story: 40
        }
    }

    var tempo: Float {
        switch self {
        case .natural, .broadcast: 1
        case .calm: 0.94
        case .happy: 1.06
        case .story: 0.92
        }
    }

    /// Silence inserted between sentence groups, in seconds.
    var pause: Double {
        switch self {
        case .natural: 0.25
        case .calm: 0.45
        case .happy: 0.18
        case .broadcast: 0.35
        case .story: 0.6
        }
    }
}

enum SpeechSpeed: String, CaseIterable, Identifiable, Codable {
    case slow, normal, fast

    var id: Self { self }

    var title: String {
        switch self {
        case .slow: "慢"
        case .normal: "正常"
        case .fast: "快"
        }
    }

    var rate: Float {
        switch self {
        case .slow: 0.85
        case .normal: 1
        case .fast: 1.2
        }
    }
}
