import AppKit
import SwiftUI

/// Multiline editor that paints emotion tags as pills and tints each segment like the promo UI.
struct TaggedScriptEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: TextSelection?
    var defaultStyle: SpeechStyle
    /// Width from SwiftUI layout; AppKit otherwise often wraps at ~half the panel.
    var layoutWidth: CGFloat
    var isEnabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ScriptScrollView {
        let scroll = ScriptScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true

        let textView = TaggedNSTextView()
        textView.isRichText = true
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.enabledTextCheckingTypes = 0
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 5, height: 4)
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.insertionPointColor = NSColor.kpCyan
        textView.defaultStyle = defaultStyle
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scroll.documentView = textView
        scroll.textView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scroll
        textView.string = context.coordinator.parent.text
        textView.applyTagStyles()
        scroll.layoutWidth = layoutWidth
        scroll.reflowText()
        return scroll
    }

    func updateNSView(_ scrollView: ScriptScrollView, context: Context) {
        guard let textView = scrollView.textView else { return }
        textView.isEditable = isEnabled
        textView.defaultStyle = defaultStyle
        context.coordinator.parent = self
        scrollView.layoutWidth = layoutWidth
        scrollView.reflowText()
        if context.coordinator.isUpdatingFromView { return }
        if textView.string != text {
            context.coordinator.isUpdatingFromView = true
            textView.string = text
            textView.applyTagStyles()
            context.coordinator.isUpdatingFromView = false
        } else {
            textView.applyTagStyles()
        }
        scrollView.reflowText()
        context.coordinator.syncSelection(to: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TaggedScriptEditor
        fileprivate weak var textView: TaggedNSTextView?
        fileprivate weak var scrollView: ScriptScrollView?
        var isUpdatingFromView = false

        init(_ parent: TaggedScriptEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView, !isUpdatingFromView else { return }
            isUpdatingFromView = true
            parent.text = textView.string
            textView.applyTagStyles()
            scrollView?.reflowText()
            isUpdatingFromView = false
            syncSelection(from: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            syncSelection(from: textView)
        }

        private func syncSelection(from textView: NSTextView) {
            let range = textView.selectedRange()
            guard range.location <= parent.text.utf16.count else { return }
            let start = parent.text.utf16.index(parent.text.utf16.startIndex, offsetBy: range.location)
            let end = parent.text.utf16.index(start, offsetBy: range.length, limitedBy: parent.text.utf16.endIndex) ?? start
            let startIndex = String.Index(start, within: parent.text) ?? parent.text.startIndex
            let endIndex = String.Index(end, within: parent.text) ?? startIndex
            parent.selection = TextSelection(range: startIndex..<endIndex)
        }

        func syncSelection(to textView: NSTextView) {
            guard let selection = parent.selection else { return }
            if case .selection(let range) = selection.indices,
               range.lowerBound >= parent.text.startIndex, range.upperBound <= parent.text.endIndex {
                let loc = parent.text.distance(from: parent.text.startIndex, to: range.lowerBound)
                let len = parent.text.distance(from: range.lowerBound, to: range.upperBound)
                let ns = NSRange(location: loc, length: len)
                if textView.selectedRange() != ns {
                    textView.setSelectedRange(ns)
                }
            }
        }
    }
}

/// Keeps the text view as wide as the SwiftUI panel so lines wrap edge-to-edge.
final class ScriptScrollView: NSScrollView {
    weak var textView: TaggedNSTextView?
    var layoutWidth: CGFloat = 0

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        super.layout()
        reflowText()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        reflowText()
    }

    func reflowText() {
        guard let textView, let container = textView.textContainer, let manager = textView.layoutManager else { return }
        let clipWidth = contentView.bounds.width
        let width = max(layoutWidth, clipWidth, 1)
        let contentWidth = max(width - textView.textContainerInset.width * 2, 1)

        var frame = textView.frame
        frame.origin = .zero
        frame.size.width = width
        textView.frame = frame
        container.containerSize = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)

        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        frame.size.height = max(used.height + textView.textContainerInset.height * 2, contentView.bounds.height)
        textView.frame = frame
        textView.needsDisplay = true
    }
}

final class TaggedNSTextView: NSTextView {
    var defaultStyle: SpeechStyle = .natural
    /// Label character range (without brackets) and accent of each recognised tag.
    private(set) var tagPills: [(range: NSRange, accent: NSColor)] = []

    /// Pill geometry, matching `EmotionTagPill`.
    private static let pillPadX: CGFloat = 10
    private static let pillPadY: CGFloat = 3
    /// Gap between a pill and the text around it.
    private static let pillGapBefore: CGFloat = 2
    private static let pillGapAfter: CGFloat = 6
    private static let pillFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let pillBaselineOffset: CGFloat = 1

    override func draw(_ dirtyRect: NSRect) {
        drawTagPills()
        super.draw(dirtyRect)
    }

    func applyTagStyles() {
        tagPills.removeAll()
        let plain = string as NSString
        let full = NSRange(location: 0, length: plain.length)
        textStorage?.setAttributes(baseAttributes(for: defaultStyle), range: full)

        var currentStyle = defaultStyle
        var index = 0
        while index < plain.length {
            if plain.character(at: index) == UInt16(("[" as UnicodeScalar).value) {
                let close = (plain.substring(from: index) as NSString).range(of: "]").location
                guard close != NSNotFound else { index += 1; continue }
                let closeIndex = index + close
                let nameRange = NSRange(location: index + 1, length: close - 1)
                let name = plain.substring(with: nameRange)
                if let style = StyledScript.style(named: name) {
                    currentStyle = style
                    let openBracket = NSRange(location: index, length: 1)
                    let labelRange = NSRange(location: index + 1, length: close - 1)
                    let closeBracket = NSRange(location: closeIndex, length: 1)
                    // The pill is painted behind the text, so the layout itself must make room
                    // for its padding: kerning after the hidden "[", after the label's last
                    // character, and after the hidden "]".
                    textStorage?.setAttributes(
                        invisibleBracketAttributes(kern: Self.pillGapBefore + Self.pillPadX), range: openBracket)
                    textStorage?.setAttributes(pillLabelAttributes(for: style), range: labelRange)
                    textStorage?.addAttribute(
                        .kern, value: Self.pillPadX,
                        range: NSRange(location: labelRange.upperBound - 1, length: 1))
                    textStorage?.setAttributes(invisibleBracketAttributes(kern: Self.pillGapAfter), range: closeBracket)
                    tagPills.append((labelRange, style.tagAccentNSColor))
                    index = closeIndex + 1
                    continue
                }
            }
            let remainder = plain.substring(from: index) as NSString
            let nextOpen = remainder.range(of: "[").location
            let segmentLength = nextOpen == NSNotFound ? remainder.length : nextOpen
            let segmentRange = NSRange(location: index, length: segmentLength)
            if segmentLength > 0 {
                textStorage?.setAttributes(bodyAttributes(for: currentStyle), range: segmentRange)
            }
            index += max(segmentLength, 1)
        }
        needsDisplay = true
    }

    private func drawTagPills() {
        guard let manager = layoutManager else { return }
        let origin = textContainerOrigin
        let font = Self.pillFont
        let labelHeight = font.ascender - font.descender
        for pill in tagPills {
            var actual = NSRange()
            let glyphRange = manager.glyphRange(forCharacterRange: pill.range, actualCharacterRange: &actual)
            guard glyphRange.length > 0 else { continue }
            // Horizontal extent from the label glyphs, excluding the kern that reserves padding.
            let firstGlyph = glyphRange.location
            let lastGlyph = glyphRange.upperBound - 1
            let lineRect = manager.lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: nil)
            let startX = lineRect.minX + manager.location(forGlyphAt: firstGlyph).x
            let lastLineRect = manager.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
            let endX: CGFloat
            if lastLineRect.minY == lineRect.minY {
                let lastChar = (string as NSString).substring(with: NSRange(location: pill.range.upperBound - 1, length: 1))
                let advance = (lastChar as NSString).size(withAttributes: [.font: font]).width
                endX = lineRect.minX + manager.location(forGlyphAt: lastGlyph).x + advance
            } else {
                // The label wrapped; keep the pill on its first line.
                endX = manager.lineFragmentUsedRect(forGlyphAt: firstGlyph, effectiveRange: nil).maxX - Self.pillPadX
            }
            // Vertical extent from the label font around its baseline, not the taller body line.
            let baselineY = lineRect.minY + manager.location(forGlyphAt: firstGlyph).y - Self.pillBaselineOffset
            let labelTop = baselineY - font.ascender
            let pillRect = NSRect(
                x: origin.x + startX - Self.pillPadX,
                y: origin.y + labelTop - Self.pillPadY,
                width: max(endX - startX, 0) + Self.pillPadX * 2,
                height: labelHeight + Self.pillPadY * 2
            ).insetBy(dx: 0.5, dy: 0.5)
            let radius = pillRect.height / 2
            let path = NSBezierPath(roundedRect: pillRect, xRadius: radius, yRadius: radius)
            pill.accent.withAlphaComponent(0.16).setFill()
            path.fill()
            pill.accent.withAlphaComponent(0.72).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func baseAttributes(for style: SpeechStyle) -> [NSAttributedString.Key: Any] {
        bodyAttributes(for: style)
    }

    private func bodyAttributes(for _: SpeechStyle) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.kpText,
            .paragraphStyle: paragraph,
            .underlineStyle: 0,
        ]
    }

    private func pillLabelAttributes(for style: SpeechStyle) -> [NSAttributedString.Key: Any] {
        let accent = style.tagAccentNSColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: Self.pillFont,
            .foregroundColor: accent,
            .paragraphStyle: paragraph,
            .baselineOffset: Self.pillBaselineOffset,
            .underlineStyle: 0,
        ]
    }

    /// Brackets stay in the string for editing but are invisible; `kern` is the space they
    /// reserve after themselves for the pill's padding and gap.
    private func invisibleBracketAttributes(kern: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: NSFont.systemFont(ofSize: 0.001),
            .foregroundColor: NSColor.clear,
            .kern: kern,
            .paragraphStyle: paragraph,
            .underlineStyle: 0,
        ]
    }
}

private extension NSColor {
    static let kpText = NSColor(red: 0.914, green: 0.969, blue: 0.973, alpha: 1)
    static let kpCyan = NSColor(red: 0.251, green: 0.902, blue: 0.949, alpha: 1)
}
