import Foundation

/// Text with inline emotion tags, e.g. `[生气]我这次真的生气了，[害怕]我真被吓到了。`
/// A tag applies until the next tag; text before the first tag uses the default style.
struct StyledScript {
    struct Segment: Equatable {
        let style: SpeechStyle
        let text: String
    }

    let segments: [Segment]
    /// Bracketed words that weren't recognised as a style; they are dropped from the spoken text.
    let unknownTags: [String]
    private let hasRecognisedTag: Bool

    var usesTags: Bool { hasRecognisedTag || !unknownTags.isEmpty }

    init(_ text: String, defaultStyle: SpeechStyle) {
        var segments: [Segment] = []
        var unknown: [String] = []
        var style = defaultStyle
        var buffer = ""
        var sawTag = false

        func flush() {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { segments.append(Segment(style: style, text: trimmed)) }
            buffer = ""
        }

        var remaining = Substring(text)
        while let match = remaining.firstMatch(of: Self.tagPattern) {
            buffer += remaining[..<match.range.lowerBound]
            let word = String(match.output.1).trimmingCharacters(in: .whitespaces)
            if let tagged = Self.style(named: word) {
                flush()
                style = tagged
                sawTag = true
            } else {
                unknown.append(word)
            }
            remaining = remaining[match.range.upperBound...]
        }
        buffer += remaining
        flush()

        self.segments = segments
        self.unknownTags = unknown
        self.hasRecognisedTag = sawTag
    }

    /// Matches `[生气]` and `【生气】`, up to 8 characters inside.
    nonisolated(unsafe) private static let tagPattern = #/[\[【]([^\[\]【】\n]{1,8})[\]】]/#

    static func style(named word: String) -> SpeechStyle? {
        if let style = SpeechStyle.allCases.first(where: { $0.title == word || $0.rawValue == word.lowercased() }) {
            return style
        }
        return aliases[word]
    }

    private static let aliases: [String: SpeechStyle] = [
        "正常": .natural, "普通": .natural,
        "冷静": .calm, "淡定": .calm,
        "亲切": .gentle, "温和": .gentle,
        "高兴": .happy, "快乐": .happy, "愉快": .happy, "欢快": .happy, "笑": .happy,
        "激动": .excited, "兴奋地": .excited,
        "难过": .sad, "伤心": .sad, "哭": .sad, "悲痛": .sad,
        "愤怒": .angry, "生气地": .angry, "发火": .angry, "怒": .angry,
        "吃惊": .surprised, "震惊": .surprised,
        "恐惧": .scared, "害怕地": .scared, "紧张": .scared, "惊恐": .scared,
        "认真": .serious, "严厉": .serious,
        "撒娇地": .coquettish, "可爱": .coquettish,
        "新闻": .broadcast, "主播": .broadcast,
        "故事": .story, "讲述": .story,
        "广告配音": .advertisement,
        "悄悄话": .whisper, "小声": .whisper, "低语": .whisper,
    ]
}
