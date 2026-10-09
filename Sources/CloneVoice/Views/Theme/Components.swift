import SwiftUI

struct KPProgressBar: View {
    var value: Double
    var isComplete = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.07))
                Capsule()
                    .fill(isComplete
                        ? LinearGradient(colors: [.kpGold, Color(red: 1, green: 0.85, blue: 0.5)], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [.kpTeal, .kpCyan, .kpGold], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
                    .shadow(color: (isComplete ? Color.kpGold : .kpCyan).opacity(0.6), radius: 4)
            }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.2), value: value)
    }
}

/// Pill segmented control in the site's chip style.
struct KPSegmented<Option: Hashable & Identifiable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button { withAnimation(.snappy(duration: 0.22)) { selection = option } } label: {
                    Text(title(option))
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .foregroundStyle(isSelected ? Color.kpText : .kpMuted)
                        .background {
                            if isSelected { KPChipHighlight().matchedGeometryEffect(id: "chip", in: indicator) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.kpLine))
    }
}

/// Selected-chip fill shared by the style and speed pickers.
struct KPChipHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.kpCyan.opacity(0.2))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.kpCyan.opacity(0.4)))
            .shadow(color: .kpCyan.opacity(0.3), radius: 6)
    }
}

/// Glowing gradient disc with the voice's first character.
struct VoiceAvatar: View {
    var name = ""
    var size: CGFloat = 28

    private var palette: [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.62, green: 0.96, blue: 0.98), .kpTeal],
            [Color(red: 1, green: 0.85, blue: 0.54), .kpGold],
            [Color(red: 0.78, green: 0.84, blue: 1), Color(red: 0.49, green: 0.61, blue: 1)],
            [Color(red: 0.6, green: 0.98, blue: 0.82), Color(red: 0.13, green: 0.7, blue: 0.55)],
        ]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palettes[hash % palettes.count]
    }

    var body: some View {
        Text(name.first.map(String.init) ?? "声")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Color.kpInk)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            .shadow(color: palette[1].opacity(0.45), radius: size * 0.2)
    }
}

struct PlayButton: View {
    var isPlaying: Bool
    var size: CGFloat = 32
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isPlaying {
                    Circle()
                        .stroke(Color.kpCyan.opacity(0.5), lineWidth: 1)
                        .frame(width: size, height: size)
                        .phaseAnimator([false, true]) { ring, isOut in
                            ring.scaleEffect(isOut ? 1.55 : 1).opacity(isOut ? 0 : 0.8)
                        } animation: { isOut in isOut ? .easeOut(duration: 1.1) : nil }
                }
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(Color.kpInk)
                    .offset(x: isPlaying ? 0 : size * 0.03)
                    .frame(width: size, height: size)
                    .background(.kpPrimary, in: Circle())
                    .shadow(color: .kpCyan.opacity(isHovered || isPlaying ? 0.6 : 0.3), radius: isHovered ? 8 : 5)
                    .scaleEffect(isHovered ? 1.06 : 1)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.15), value: isHovered)
        .help(isPlaying ? "停止" : "播放")
    }
}

/// Plain field on a frosted panel, replacing the stock rounded border.
struct KPFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .kpPanel(cornerRadius: 9)
    }
}

extension TextFieldStyle where Self == KPFieldStyle {
    static var kp: KPFieldStyle { KPFieldStyle() }
}

struct KPDivider: View {
    var body: some View {
        Rectangle().fill(Color.kpLine).frame(height: 1)
    }
}
