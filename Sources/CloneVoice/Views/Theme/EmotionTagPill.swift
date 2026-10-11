import SwiftUI

/// Inline emotion chip matching the promo film: dark glass fill, colored stroke and label.
struct EmotionTagPill: View {
    let title: String
    var accent: Color

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(accent.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(accent.opacity(0.72), lineWidth: 1))
    }
}

/// Read-only script line with pills and segment-colored body text.
struct TaggedScriptPreview: View {
    let text: String
    var defaultStyle: SpeechStyle
    var fontSize: CGFloat = 18

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 8) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                switch piece {
                case .tag(let title, let accent):
                    EmotionTagPill(title: title, accent: accent)
                case .text(let string, let accent):
                    Text(string)
                        .font(.system(size: fontSize, weight: .medium))
                        .foregroundStyle(accent)
                }
            }
        }
    }

    private enum Piece {
        case tag(title: String, accent: Color)
        case text(String, accent: Color)
    }

    private var pieces: [Piece] {
        var result: [Piece] = []
        var currentStyle = defaultStyle
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "[", let close = text[index...].firstIndex(of: "]") {
                let inner = text[text.index(after: index)..<close]
                let name = String(inner)
                if let style = StyledScript.style(named: name) {
                    currentStyle = style
                    result.append(.tag(title: name, accent: style.tagAccent))
                    index = text.index(after: close)
                    continue
                }
            }
            let nextTag = text[index...].firstIndex(of: "[") ?? text.endIndex
            let chunk = String(text[index..<nextTag])
            if !chunk.isEmpty {
                result.append(.text(chunk, accent: currentStyle.tagAccent))
            }
            index = nextTag
        }
        return result
    }
}

/// Wraps children left-to-right, breaking onto new lines at the given width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let rows = rows(for: width, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var height: CGFloat = 0
    }

    private func rows(for maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        var x: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                rows.append(Row())
                x = 0
            }
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            x += size.width + spacing
        }
        return rows
    }
}
