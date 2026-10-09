import SwiftUI

/// Palette shared with voice.kunpeng.si: deep teal night, cyan voice, gold accents.
extension Color {
    static let kpBackground = Color(red: 0.016, green: 0.078, blue: 0.090)
    static let kpBackground2 = Color(red: 0.024, green: 0.125, blue: 0.149)
    static let kpPanel = Color(red: 0.04, green: 0.17, blue: 0.20).opacity(0.55)
    static let kpLine = Color(red: 0.47, green: 0.90, blue: 0.94).opacity(0.14)
    static let kpLineStrong = Color(red: 0.47, green: 0.90, blue: 0.94).opacity(0.32)
    static let kpCyan = Color(red: 0.251, green: 0.902, blue: 0.949)
    static let kpTeal = Color(red: 0.075, green: 0.706, blue: 0.761)
    static let kpGold = Color(red: 0.965, green: 0.714, blue: 0.282)
    static let kpCoral = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let kpText = Color(red: 0.914, green: 0.969, blue: 0.973)
    static let kpMuted = Color(red: 0.553, green: 0.698, blue: 0.718)
    static let kpInk = Color(red: 0.012, green: 0.125, blue: 0.145)
}

extension ShapeStyle where Self == LinearGradient {
    static var kpPrimary: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.5, green: 0.95, blue: 0.98), .kpCyan, .kpTeal],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static var kpTitle: LinearGradient {
        LinearGradient(colors: [.white, Color(red: 0.62, green: 0.96, blue: 0.98), .kpGold], startPoint: .leading, endPoint: .trailing)
    }
}

/// Cyan glass button with a glow, the site's primary CTA.
struct KPPrimaryButtonStyle: ButtonStyle {
    var isLarge = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: isLarge ? 14 : 13, weight: .semibold))
            .foregroundStyle(Color.kpInk)
            .padding(.horizontal, isLarge ? 20 : 16)
            .frame(height: isLarge ? 38 : 30)
            .background(.kpPrimary, in: RoundedRectangle(cornerRadius: isLarge ? 11 : 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: isLarge ? 11 : 9, style: .continuous)
                    .strokeBorder(.white.opacity(0.45), lineWidth: 0.5)
            )
            .shadow(color: .kpCyan.opacity(isEnabled ? (configuration.isPressed ? 0.25 : 0.45) : 0), radius: 10, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Outlined glass button for secondary actions.
struct KPGhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.kpText)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Color.kpCyan.opacity(isHovered ? 0.1 : 0.03), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isHovered ? Color.kpCyan.opacity(0.6) : .kpLineStrong)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovered = $0 }
            .animation(.snappy(duration: 0.15), value: isHovered)
    }
}

extension ButtonStyle where Self == KPPrimaryButtonStyle {
    static var kpPrimary: KPPrimaryButtonStyle { KPPrimaryButtonStyle() }
    static var kpPrimaryLarge: KPPrimaryButtonStyle { KPPrimaryButtonStyle(isLarge: true) }
}

extension ButtonStyle where Self == KPGhostButtonStyle {
    static var kpGhost: KPGhostButtonStyle { KPGhostButtonStyle() }
}

extension View {
    /// Frosted teal card with a hairline cyan border.
    func kpPanel(cornerRadius: CGFloat = 14, isHighlighted: Bool = false) -> some View {
        background(Color.kpPanel, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isHighlighted ? Color.kpCyan.opacity(0.45) : .kpLine)
            )
            .shadow(color: .kpCyan.opacity(isHighlighted ? 0.18 : 0), radius: 18)
    }

    /// Dark night backdrop, cyan tint and dark controls for every window and sheet.
    func kpWindowTheme() -> some View {
        preferredColorScheme(.dark)
            .tint(.kpCyan)
            .foregroundStyle(Color.kpText)
    }

    func kpSheet() -> some View {
        kpWindowTheme()
            .background {
                ZStack {
                    Color.kpBackground
                    RadialGradient(colors: [.kpTeal.opacity(0.16), .clear], center: .topTrailing, startRadius: 0, endRadius: 520)
                }
                .ignoresSafeArea()
            }
    }
}
