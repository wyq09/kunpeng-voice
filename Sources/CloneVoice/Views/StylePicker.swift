import SwiftUI

/// Featured styles as chips, everything else under "更多" so the toolbar stays short.
struct StylePicker: View {
    @Binding var selection: SpeechStyle
    /// The active model can't follow style instructions, so styles are prosody approximations.
    var isApproximate: Bool
    var onOpenModels: () -> Void

    private var chips: [SpeechStyle] {
        SpeechStyle.featured.contains(selection) ? SpeechStyle.featured : SpeechStyle.featured + [selection]
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(chips) { item in
                    Button { selection = item } label: {
                        Text(item.title)
                            .font(.callout)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background {
                                if item == selection {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(.background)
                                        .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(item == selection ? .primary : .secondary)
                }

                Menu {
                    ForEach(SpeechStyle.Group.allCases) { group in
                        Section(group.title) {
                            ForEach(SpeechStyle.styles(in: group)) { item in
                                Toggle(item.title, isOn: Binding(
                                    get: { selection == item },
                                    set: { if $0 { selection = item } }
                                ))
                            }
                        }
                    }
                    if isApproximate {
                        Divider()
                        Button("当前模型的情绪为近似效果，换用 CosyVoice 3…", action: onOpenModels)
                    }
                } label: {
                    Text("更多").font(.callout)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 6)
            }
            .padding(2)
            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))
            .help("说话的情绪和风格")

            if isApproximate {
                Button(action: onOpenModels) {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("当前模型的情绪为近似效果。点此换用支持情绪指令的模型（CosyVoice 3 / VoxCPM）")
            }
        }
    }
}
