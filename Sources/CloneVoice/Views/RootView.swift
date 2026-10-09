import AppKit
import SwiftUI

enum SidebarItem: Hashable {
    case newVoice
    case voice(Voice.ID)
}

struct RootView: View {
    @Environment(VoiceStore.self) private var store
    @Environment(VoiceEngine.self) private var engine
    @Environment(ModelManager.self) private var models
    @Environment(AgentSetup.self) private var agentSetup
    @Environment(SmartPhrasing.self) private var phrasing
    @State private var selection: SidebarItem?

    /// Changes whenever the model that should be in memory changes.
    private var engineKey: String { "\(models.activeID)|\(models.isActiveDownloaded)" }

    var body: some View {
        @Bindable var models = models
        @Bindable var agentSetup = agentSetup
        @Bindable var phrasing = phrasing
        NavigationSplitView {
            Sidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { AmbientBackground() }
        }
        .kpWindowTheme()
        .onAppear {
            selection = store.voices.first.map { .voice($0.id) } ?? .newVoice
            models.downloadActiveIfNothingInstalled()
            if ProcessInfo.processInfo.environment["KP_NEW"] != nil { selection = .newVoice }
        }
        .task(id: engineKey) {
            if models.isActiveDownloaded {
                engine.load(models.activeSpec, from: models.directory(for: models.activeSpec))
            } else {
                engine.unload()
            }
        }
        .sheet(isPresented: $models.isPresented) { ModelManagerView().kpSheet() }
        .sheet(isPresented: $agentSetup.isPresented) { AgentSetupView().kpSheet() }
        .sheet(isPresented: $phrasing.isPresented) { SmartPhrasingView().kpSheet() }
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
    @Environment(Player.self) private var player
    @Environment(JobStore.self) private var jobs
    @Environment(Generator.self) private var generator
    @Binding var selection: SidebarItem?

    @State private var renaming: Voice?
    @State private var newName = ""
    @State private var deleting: Voice?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    Text("声音")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.kpMuted.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.bottom, 2)
                    ForEach(store.voices) { voice in
                        SidebarRow(
                            isSelected: selection == .voice(voice.id),
                            action: { selection = .voice(voice.id) }
                        ) {
                            VoiceAvatar(name: voice.name)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(voice.name).lineLimit(1)
                                Text(voice.subtitle).font(.caption).foregroundStyle(Color.kpMuted)
                            }
                            Spacer(minLength: 0)
                            if generator.isGenerating(voice.id) || jobs.jobs.contains(where: { $0.isRunning && $0.voiceName == voice.name }) {
                                GeneratingWave().frame(width: 26, height: 14).help("正在生成")
                            }
                        }
                        .contextMenu {
                            Button("重命名…") { startRenaming(voice) }
                            Divider()
                            Button("删除…", role: .destructive) { deleting = voice }
                        }
                    }
                    SidebarRow(isSelected: selection == .newVoice, action: { selection = .newVoice }) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.kpCyan)
                            .frame(width: 28, height: 28)
                            .background(Color.kpCyan.opacity(0.08), in: Circle())
                            .overlay(Circle().strokeBorder(Color.kpCyan.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        Text("创建声音").foregroundStyle(Color.kpMuted)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }
            .scrollIndicators(.never)
            VStack(spacing: 0) {
                KPDivider().padding(.horizontal, 14)
                AgentSetupButton()
                ModelStatusView()
            }
        }
        .background {
            ZStack {
                Color.kpBackground2
                LinearGradient(colors: [.kpTeal.opacity(0.12), .clear, .kpGold.opacity(0.04)], startPoint: .top, endPoint: .bottom)
                HStack { Spacer(); Rectangle().fill(Color.kpLine).frame(width: 1) }
            }
            .ignoresSafeArea()
        }
        .alert("重命名声音", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名字", text: $newName)
            Button("取消", role: .cancel) {}
            Button("保存") {
                if let renaming { store.rename(renaming.id, to: newName) }
            }
        }
        .confirmationDialog(
            "删除「\(deleting?.name ?? "")」？",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("删除", role: .destructive) {
                guard let deleting else { return }
                player.stop()
                store.delete(deleting.id)
                if selection == .voice(deleting.id) {
                    selection = store.voices.first.map { .voice($0.id) } ?? .newVoice
                }
            }
        } message: {
            Text("声音样本和它生成的音频都会被删除。")
        }
    }

    private func startRenaming(_ voice: Voice) {
        newName = voice.name
        renaming = voice
    }

    private var header: some View {
        HStack(spacing: 10) {
            Group {
                if let icon = AppBrandIcon.image() {
                    Image(nsImage: icon)
                        .resizable()
                } else {
                    Image(systemName: "waveform.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.kpCyan, Color.kpTeal)
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .kpCyan.opacity(0.4), radius: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text("鲲鹏有声")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.kpTitle)
                Text("你的声音，读出一切")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.kpMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

/// Sidebar entry with a glowing cyan selection, replacing the system accent highlight.
private struct SidebarRow<Content: View>: View {
    var isSelected: Bool
    var action: () -> Void
    @ViewBuilder var content: Content
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { content }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.kpCyan.opacity(0.14) : .white.opacity(isHovered ? 0.04 : 0))
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.kpCyan.opacity(0.32))
                            .shadow(color: .kpCyan.opacity(0.35), radius: 6)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.18), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct AgentSetupButton: View {
    @Environment(AgentSetup.self) private var agentSetup

    var body: some View {
        Button { agentSetup.isPresented = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "puzzlepiece.extension")
                Text("接入 Agent")
                Spacer(minLength: 0)
                Text("MCP · 命令行").foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(Color.kpMuted)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("让 Claude Code、Cursor、Codex 等用你的声音说话")
    }
}

/// Sidebar footer: always says what the model is doing and opens model management on click.
private struct ModelStatusView: View {
    @Environment(VoiceEngine.self) private var engine
    @Environment(ModelManager.self) private var models

    var body: some View {
        Button { models.isPresented = true } label: {
            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("模型管理（⌘,）")
    }

    @ViewBuilder
    private var content: some View {
        let spec = models.activeSpec
        switch models.status(of: spec) {
        case .downloading(let fraction):
            status(color: .kpGold, text: "正在下载 \(spec.name) \(Int(fraction * 100))%")
            KPProgressBar(value: fraction)
            Text("只需下载一次，之后可离线使用").font(.caption2).foregroundStyle(.tertiary)
        case .failed(let message):
            status(color: .kpCoral, text: "模型下载失败")
            Text(message).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .notDownloaded:
            status(color: .kpMuted, text: "还没有模型 · 点此下载")
        case .downloaded:
            switch engine.phase {
            case .idle, .loading:
                status(color: .kpGold, text: "正在加载 \(spec.name)…")
            case .ready:
                status(color: .kpCyan, text: "\(spec.name) · 就绪")
            case .failed(let message):
                status(color: .kpCoral, text: "模型加载失败")
                Text(message).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func status(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7).shadow(color: color, radius: 4)
            Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
        }
    }
}
