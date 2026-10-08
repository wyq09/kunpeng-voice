import SwiftUI

enum SidebarItem: Hashable {
    case jobs
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
                .background(.background)
        }
        .onAppear {
            selection = store.voices.first.map { .voice($0.id) } ?? .newVoice
            models.downloadActiveIfNothingInstalled()
        }
        .task(id: engineKey) {
            if models.isActiveDownloaded {
                engine.load(models.activeSpec, from: models.directory(for: models.activeSpec))
            } else {
                engine.unload()
            }
        }
        .sheet(isPresented: $models.isPresented) { ModelManagerView() }
        .sheet(isPresented: $agentSetup.isPresented) { AgentSetupView() }
        .sheet(isPresented: $phrasing.isPresented) { SmartPhrasingView() }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .jobs:
            JobsView()
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
    @Binding var selection: SidebarItem?

    @State private var renaming: Voice?
    @State private var newName = ""
    @State private var deleting: Voice?

    var body: some View {
        List(selection: $selection) {
            Label("生成任务", systemImage: "list.bullet.rectangle")
                .badge(jobs.runningCount)
                .padding(.vertical, 3)
                .tag(SidebarItem.jobs)
                .help("应用、MCP、命令行的所有生成，实时进度")
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
                    .contextMenu {
                        Button("重命名…") { startRenaming(voice) }
                        Divider()
                        Button("删除…", role: .destructive) { deleting = voice }
                    }
                }
                Label("新建声音", systemImage: "plus")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 3)
                    .tag(SidebarItem.newVoice)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                AgentSetupButton()
                ModelStatusView()
            }
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
        HStack(spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 28, height: 28)
            Text("鲲鹏有声").font(.headline)
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
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 8)
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
            status(color: .orange, text: "正在下载 \(spec.name) \(Int(fraction * 100))%")
            ProgressView(value: fraction).controlSize(.mini)
            Text("只需下载一次，之后可离线使用").font(.caption2).foregroundStyle(.tertiary)
        case .failed(let message):
            status(color: .red, text: "模型下载失败")
            Text(message).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .notDownloaded:
            status(color: .gray, text: "还没有模型 · 点此下载")
        case .downloaded:
            switch engine.phase {
            case .idle, .loading:
                status(color: .orange, text: "正在加载 \(spec.name)…")
            case .ready:
                status(color: .green, text: "\(spec.name) · 就绪")
            case .failed(let message):
                status(color: .red, text: "模型加载失败")
                Text(message).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func status(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
        }
    }
}
