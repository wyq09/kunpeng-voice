import Foundation

/// Models that accept style instructions (CosyVoice 3) receive `instruction`.
/// Models that don't (Qwen3-TTS clone mode) approximate the style through
/// sampling temperature and prosody: pitch, tempo and sentence pauses.
enum SpeechStyle: String, CaseIterable, Identifiable, Codable {
    case natural, calm, gentle, happy, excited
    case sad, angry, surprised, scared, serious, coquettish
    case broadcast, story, advertisement, whisper

    enum Group: CaseIterable, Identifiable {
        case common, emotion, scene

        var id: Self { self }

        var title: String {
            switch self {
            case .common: "常用"
            case .emotion: "情绪"
            case .scene: "场景"
            }
        }
    }

    var id: Self { self }

    /// Shown directly in the toolbar; the rest live under "更多".
    static let featured: [SpeechStyle] = [.natural, .calm, .happy, .broadcast, .story]

    var group: Group {
        switch self {
        case .natural, .calm, .gentle, .happy, .excited: .common
        case .sad, .angry, .surprised, .scared, .serious, .coquettish: .emotion
        case .broadcast, .story, .advertisement, .whisper: .scene
        }
    }

    var title: String {
        switch self {
        case .natural: "自然"
        case .calm: "平静"
        case .gentle: "温柔"
        case .happy: "开心"
        case .excited: "兴奋"
        case .sad: "悲伤"
        case .angry: "生气"
        case .surprised: "惊讶"
        case .scared: "害怕"
        case .serious: "严肃"
        case .coquettish: "撒娇"
        case .broadcast: "播音"
        case .story: "讲故事"
        case .advertisement: "广告"
        case .whisper: "耳语"
        }
    }

    var instruction: String? {
        switch self {
        case .natural: nil
        case .calm: "请用平静、舒缓的语气说这句话。"
        case .gentle: "请用温柔、亲切的语气说这句话。"
        case .happy: "请用非常开心的语气说这句话。"
        case .excited: "请用兴奋、激动的语气说这句话。"
        case .sad: "请用悲伤、难过的语气说这句话。"
        case .angry: "请用生气、愤怒的语气说这句话。"
        case .surprised: "请用惊讶的语气说这句话。"
        case .scared: "请用害怕、紧张的语气说这句话。"
        case .serious: "请用严肃、认真的语气说这句话。"
        case .coquettish: "请用撒娇的语气说这句话。"
        case .broadcast: "请像新闻主播一样，用标准、清晰的播音腔说这句话。"
        case .story: "请像给孩子讲睡前故事一样，娓娓道来地说这句话。"
        case .advertisement: "请用热情、有感染力的广告配音语气说这句话。"
        case .whisper: "请用轻声耳语的方式说这句话。"
        }
    }

    /// Short voice description for models that take a parenthesised style prefix (VoxCPM 2).
    var styleDescription: String? {
        switch self {
        case .natural: nil
        case .calm: "平静舒缓"
        case .gentle: "温柔亲切"
        case .happy: "开心愉快"
        case .excited: "兴奋激动"
        case .sad: "悲伤难过，略带哽咽"
        case .angry: "生气愤怒"
        case .surprised: "惊讶"
        case .scared: "害怕紧张，声音发颤"
        case .serious: "严肃认真"
        case .coquettish: "撒娇，软糯"
        case .broadcast: "新闻主播，字正腔圆"
        case .story: "讲睡前故事，娓娓道来"
        case .advertisement: "热情的广告配音"
        case .whisper: "轻声耳语"
        }
    }

    var prosody: Prosody {
        switch self {
        case .natural: Prosody(temperature: 0.9, pitchCents: 0, tempo: 1, pause: 0.25)
        case .calm: Prosody(temperature: 0.65, pitchCents: -60, tempo: 0.94, pause: 0.45)
        case .gentle: Prosody(temperature: 0.7, pitchCents: -30, tempo: 0.95, pause: 0.35)
        case .happy: Prosody(temperature: 1.0, pitchCents: 150, tempo: 1.06, pause: 0.18)
        case .excited: Prosody(temperature: 1.05, pitchCents: 220, tempo: 1.1, pause: 0.15)
        case .sad: Prosody(temperature: 0.7, pitchCents: -120, tempo: 0.88, pause: 0.5)
        case .angry: Prosody(temperature: 1.0, pitchCents: 60, tempo: 1.08, pause: 0.15)
        case .surprised: Prosody(temperature: 1.0, pitchCents: 200, tempo: 1.02, pause: 0.25)
        case .scared: Prosody(temperature: 0.95, pitchCents: 80, tempo: 1.05, pause: 0.3)
        case .serious: Prosody(temperature: 0.6, pitchCents: -60, tempo: 0.97, pause: 0.35)
        case .coquettish: Prosody(temperature: 0.95, pitchCents: 180, tempo: 0.95, pause: 0.3)
        case .broadcast: Prosody(temperature: 0.55, pitchCents: 0, tempo: 1, pause: 0.35)
        case .story: Prosody(temperature: 0.85, pitchCents: 40, tempo: 0.92, pause: 0.6)
        case .advertisement: Prosody(temperature: 0.8, pitchCents: 80, tempo: 1.05, pause: 0.2)
        case .whisper: Prosody(temperature: 0.7, pitchCents: -40, tempo: 0.9, pause: 0.4)
        }
    }

    static func styles(in group: Group) -> [SpeechStyle] { allCases.filter { $0.group == group } }
}

struct Prosody {
    let temperature: Float
    let pitchCents: Float
    let tempo: Float
    /// Silence inserted between sentence groups, in seconds.
    let pause: Double
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
