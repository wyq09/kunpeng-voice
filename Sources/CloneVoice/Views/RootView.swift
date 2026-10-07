import SwiftUI

enum SidebarItem: Hashable {
    case newVoice
    case voice(Voice.ID)
}

struct RootView: View {
    @Environment(VoiceStore.self) private var store
    @State private var selection: SidebarItem?

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        }
        .onAppear { selection = store.voices.first.map { .voice($0.id) } ?? .newVoice }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .voice(let id) where store.voice(id: id) != nil:
            VoiceDetailView(voiceID: id, onDeleted: { selection = store.voices.first.map { .voice($0.id) } ?? .newVoice })
                .id(id)
        default:
            NewVoiceView(
                onCreated: { selection = .voice($0.id) },
                onCancel: store.voices.isEmpty ? nil : { selection = .voice(store.voices[0].id) }
            )
            .id("new")
        }
    }
}

private struct Sidebar: View {
    @Environment(VoiceStore.self) private var store
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("声音") {
                ForEach(store.voices) { voice in
                    HStack(spacing: 10) {
                        VoiceAvatar()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(voice.name).lineLimit(1)
                            Text(voice.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                    .tag(SidebarItem.voice(voice.id))
                }
                Label("新建声音", systemImage: "plus")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 3)
                    .tag(SidebarItem.newVoice)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) { ModelStatusView() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.primary, in: RoundedRectangle(cornerRadius: 7))
            Text("我的声音").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

struct VoiceAvatar: View {
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(.quaternary, in: Circle())
    }
}

private struct ModelStatusView: View {
    @Environment(VoiceEngine.self) private var engine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch engine.phase {
            case .idle:
                status(color: .gray, text: "正在检查模型…")
            case .downloading(let fraction):
                status(color: .orange, text: "正在下载模型 \(Int(fraction * 100))% · \(VoiceEngine.modelSizeText)")
                ProgressView(value: fraction).controlSize(.mini)
                Text("只需下载一次，之后可离线使用").font(.caption2).foregroundStyle(.tertiary)
            case .loading:
                status(color: .orange, text: "正在加载模型…")
            case .ready:
                status(color: .green, text: "模型就绪 · \(VoiceEngine.modelSizeText)")
            case .failed(let message):
                status(color: .red, text: "模型准备失败")
                Text(message).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("重试") { engine.prepare() }.controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func status(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}
