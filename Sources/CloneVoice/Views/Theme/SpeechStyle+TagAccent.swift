import AppKit
import SwiftUI

extension SpeechStyle {
    /// One distinct accent per style on the kp dark teal palette.
    var tagAccent: Color {
        Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    var tagAccentNSColor: NSColor {
        NSColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }

    private var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .natural: (0.914, 0.969, 0.973) // kpText
        case .calm: (0.075, 0.706, 0.761) // kpTeal
        case .gentle: (0.251, 0.902, 0.949) // kpCyan
        case .happy: (0.965, 0.714, 0.282) // kpGold
        case .excited: (1.0, 0.78, 0.32)
        case .sad: (0.55, 0.72, 0.98)
        case .angry: (1.0, 0.42, 0.42) // kpCoral
        case .surprised: (1.0, 0.88, 0.45)
        case .scared: (0.78, 0.58, 0.98)
        case .serious: (0.62, 0.78, 0.82)
        case .coquettish: (1.0, 0.62, 0.78)
        case .broadcast: (0.72, 0.96, 1.0)
        case .story: (0.42, 0.88, 0.72)
        case .advertisement: (1.0, 0.52, 0.58)
        case .whisper: (0.68, 0.74, 0.92)
        }
    }
}
