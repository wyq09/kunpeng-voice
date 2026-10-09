import AppKit
import MLXAudioCore
import SwiftUI
import UniformTypeIdentifiers

struct VoiceDetailView: View {
    @Environment(VoiceStore.self) private var store
    @Environment(VoiceEngine.self) private var engine
    @Environment(ModelManager.self) private var models
    @Environment(Player.self) private var player
    @Environment(SmartPhrasing.self) private var phrasing
    @Environment(Generator.self) private var generator
    @Environment(JobStore.self) private var jobs

    let voiceID: Voice.ID
    var onDeleted: () -> Void

    @AppStorage("speechStyle") private var style: SpeechStyle = .natural
    @AppStorage("speechSpeed") private var speed: SpeechSpeed = .normal

    @State private var text = ""
    @State private var textSelection: TextSelection?
    @State private var name = ""
    @State private var isWaitingForModel = false
    @State private var localError: String?
    @State private var isConfirmingDelete = false
    @State private var referenceDraft: String?
    @State private var isHistoryExpanded = true
    @State private var isShowingJobs = false
    @FocusState private var isEditorFocused: Bool

    private var voice: Voice? { store.voice(id: voiceID) }
    private var isBusy: Bool { generator.isGenerating(voiceID) }
    private var progress: Generator.Active? { generator.active[voiceID] }
    private var errorMessage: String? { localError ?? generator.messages[voiceID] }
    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Generations of this voice still running in other processes (MCP, command line).
    private var externalJobs: [GenerationJob] {
        guard let voice else { return [] }
        return jobs.jobs.filter { $0.isRunning && $0.source != .app && $0.voiceName == voice.name }
    }

    var body: some View {
        if let voice {
            VStack(spacing: 0) {
                header(voice)
                editor
                history(voice)
                KPDivider()
                toolbar
            }
            .onAppear {
                name = voice.name
                text = generator.drafts[voiceID] ?? ""
                generator.visibleVoiceID = voiceID
                isEditorFocused = true
                if ProcessInfo.processInfo.environment["KP_PLAY"] != nil, let clip = voice.clips.first {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { player.toggle(store.fileURL(clip.fileName)) }
                }
            }
            .onDisappear {
                store.rename(voiceID, to: name)
                if generator.visibleVoiceID == voiceID { generator.visibleVoiceID = nil }
                player.stop()
            }
            .onChange(of: text) { _, newText in generator.drafts[voiceID] = newText }
            .sheet(isPresented: $isShowingJobs) { JobsSheet() }
            .onChange(of: voice.name) { _, newName in name = newName }
            .onChange(of: engine.isReady) { _, isReady in
                if isReady, isWaitingForModel { startGeneration() }
            }
            .confirmationDialog("删除「\(voice.name)」？", isPresented: $isConfirmingDelete) {
                Button("删除", role: .destructive) {
                    player.stop()
                    store.delete(voiceID)
                    onDeleted()
                }
            } message: {
                Text("声音样本和它生成的 \(voice.clips.count) 段音频都会被删除。")
            }
            .alert("校对参考文字", isPresented: Binding(
                get: { referenceDraft != nil },
                set: { if !$0 { referenceDraft = nil } }
            )) {
                TextField("录音里说的每一个字", text: Binding(
                    get: { referenceDraft ?? "" },
                    set: { referenceDraft = $0 }
                ))
                Button("取消", role: .cancel) {}
                Button("重新识别") { recognizeReference(voice) }
                Button("保存") {
                    if let referenceDraft { store.setReferenceText(voiceID, to: referenceDraft) }
                }
            } message: {
                Text("要和录音里说的一字不差（包括开头的「你好」这类口头语），否则生成时可能多读或漏读。")
            }
        }
    }

    // MARK: - Sections

    private func header(_ voice: Voice) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VoiceAvatar(name: name, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                TextField("名字", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .bold))
                    .onSubmit { store.rename(voiceID, to: name) }
                    .help("点击修改名字")
                Button { referenceDraft = voice.referenceText } label: {
                    Text("参考录音「\(voice.referenceText)」")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.kpMuted)
                .help("点击校对：要和录音里说的一字不差，否则可能多读或漏读")
            }
            Spacer(minLength: 12)
            let sampleURL = store.fileURL(voice.sampleFileName)
            Button {
                player.toggle(sampleURL)
            } label: {
                Label(player.isPlaying(sampleURL) ? "停止" : "听原声", systemImage: player.isPlaying(sampleURL) ? "stop.fill" : "waveform")
            }
            .buttonStyle(.kpGhost)
            .help(player.isPlaying(sampleURL) ? "停止" : "听原声")
            if (engine.loadedSpec ?? models.activeSpec).family == .qwen3 {
                languageMenu(voice)
            }
            Menu {
                Button("校对参考文字…") { referenceDraft = voice.referenceText }
                Divider()
                Button("删除这个声音…", role: .destructive) { isConfirmingDelete = true }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private func languageMenu(_ voice: Voice) -> some View {
        Menu {
            Picker("主语言", selection: Binding(
                get: { voice.primaryLanguage },
                set: { store.setLanguage(voiceID, to: $0) }
            )) {
                ForEach(VoiceLanguage.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(voice.primaryLanguage.title, systemImage: "globe")
                .labelStyle(.titleAndIcon)
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("主语言：Qwen3-TTS 固定用这个语言朗读，不会中途串语言")
    }

    private var editor: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("输入想让「\(name)」说的话…\n想让每一段情绪不同，可以这样写：[生气]我真的生气了。[害怕]我被吓到了。")
                        .font(.system(size: 18))
                        .lineSpacing(6)
                        .foregroundStyle(Color.kpMuted.opacity(0.55))
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text, selection: $textSelection)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 18))
                    .lineSpacing(6)
                    .focused($isEditorFocused)
                    .disabled(isBusy)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            editorFooter
        }
        .padding(12)
        .kpPanel(cornerRadius: 16, isHighlighted: isEditorFocused || isBusy)
        .overlay(alignment: .bottom) {
            if isBusy {
                GeneratingWave()
                    .frame(height: 26)
                    .padding(.horizontal, 40)
                    .offset(y: 13)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: isEditorFocused)
        .animation(.easeOut(duration: 0.3), value: isBusy)
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    private var editorFooter: some View {
        HStack(spacing: 8) {
            scriptSummary
            Spacer(minLength: 8)
            Button { phrasing.isPresented = true } label: {
                Label(phrasing.summary, systemImage: phrasing.config.isUsable ? "text.word.spacing" : "text.alignleft")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(phrasing.config.isUsable ? Color.kpCyan : .kpMuted)
            }
            .buttonStyle(.borderless)
            .help("生成前用大模型按朗读习惯断句，原文不改一个字")
            Menu {
                ForEach(SpeechStyle.Group.allCases) { group in
                    Section(group.title) {
                        ForEach(SpeechStyle.styles(in: group)) { tagStyle in
                            Button("[\(tagStyle.title)]") { insertTag(tagStyle) }
                        }
                    }
                }
            } label: {
                Label("插入情绪标签", systemImage: "tag")
                    .labelStyle(.titleAndIcon)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(isBusy)
            .help("在光标处插入标签，标签后面的文字都用这个情绪，直到下一个标签")
        }
        .font(.caption)
        .foregroundStyle(Color.kpMuted)
        .padding(.horizontal, 5)
    }

    @ViewBuilder
    private var scriptSummary: some View {
        let script = StyledScript(text, defaultStyle: style)
        if script.usesTags {
            let flow = script.segments.map(\.style.title).joined(separator: " → ")
            let unknown = script.unknownTags.isEmpty
                ? ""
                : " · 不认识「\(script.unknownTags.joined(separator: "、"))」，已跳过"
            Text("分 \(script.segments.count) 段：\(flow)\(unknown)")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(script.unknownTags.isEmpty ? Color.kpGold.opacity(0.85) : Color.kpCoral)
        }
    }

    private func insertTag(_ tagStyle: SpeechStyle) {
        let tag = "[\(tagStyle.title)]"
        if case .selection(let range) = textSelection?.indices,
           range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex {
            let offset = text.distance(from: text.startIndex, to: range.lowerBound)
            text.replaceSubrange(range, with: tag)
            textSelection = TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: offset + tag.count))
        } else {
            text += tag
        }
        isEditorFocused = true
    }

    private func history(_ voice: Voice) -> some View {
        VStack(spacing: 0) {
            if !voice.clips.isEmpty || !externalJobs.isEmpty {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { isHistoryExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(isHistoryExpanded ? 90 : 0))
                        Text("生成记录 \(voice.clips.count)")
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(Color.kpMuted)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if isHistoryExpanded, !voice.clips.isEmpty || !externalJobs.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(externalJobs) { RunningJobRow(job: $0) }
                        ForEach(voice.clips) { clip in
                            ClipRow(clip: clip, url: store.fileURL(clip.fileName)) {
                                store.deleteClip(clip.id, from: voiceID)
                            } onReuse: {
                                text = clip.text
                                if let clipStyle = clip.style { style = clipStyle }
                                if let clipSpeed = clip.speed { speed = clipSpeed }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxHeight: 200)
            }
            jobsEntry
        }
    }

    /// Everything generated by any voice, app or agent, one click below this voice's history.
    private var jobsEntry: some View {
        Button { isShowingJobs = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle")
                Text("全部生成任务")
                Text("含 MCP、命令行").foregroundStyle(.tertiary)
                Spacer()
                if jobs.runningCount > 0 {
                    GeneratingWave().frame(width: 24, height: 12)
                    Text("\(jobs.runningCount) 条进行中")
                }
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(Color.kpMuted)
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("所有声音的生成进度、模型和耗时")
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            StylePicker(
                selection: $style,
                isApproximate: !(engine.loadedSpec ?? models.activeSpec).supportsEmotionInstruction,
                onOpenModels: { models.isPresented = true }
            )
            KPSegmented(selection: $speed, options: SpeechSpeed.allCases, title: \.title)
                .fixedSize()
                .help("语速")

            statusLine
                .frame(maxWidth: .infinity, alignment: .trailing)

            if isBusy {
                Button("停止", action: cancelGeneration).buttonStyle(.kpGhost)
            }
            Button(action: startGeneration) {
                Label(isBusy ? "生成中…" : "生成", systemImage: "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: isBusy)
                    .frame(minWidth: 64)
            }
            .buttonStyle(.kpPrimaryLarge)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(trimmedText.isEmpty || isBusy)
            .help("⌘↩ 生成")
        }
        .labelsHidden()
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var statusLine: some View {
        Group {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.kpGold)
                    .help(errorMessage)
            } else if isWaitingForModel {
                Label("模型准备好后自动生成", systemImage: "hourglass")
                    .foregroundStyle(Color.kpMuted)
            } else if let progress {
                HStack(spacing: 6) {
                    TimelineView(.periodic(from: progress.startedAt, by: 1)) { context in
                        let seconds = Int(context.date.timeIntervalSince(progress.startedAt))
                        Text(progress.isPhrasing ? "智能断句中 · \(seconds) 秒"
                            : progress.total > 1 ? "第 \(progress.current)/\(progress.total) 段 · \(seconds) 秒"
                            : "生成中 · \(seconds) 秒")
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(Color.kpCyan)
            } else if !trimmedText.isEmpty {
                Text("\(trimmedText.count) 字").foregroundStyle(Color.kpMuted.opacity(0.7))
            }
        }
        .font(.caption)
        .lineLimit(1)
    }

    // MARK: - Actions

    private func startGeneration() {
        guard !trimmedText.isEmpty, !isBusy, let voice else { return }
        localError = nil
        generator.messages[voiceID] = nil
        guard engine.isReady else {
            isWaitingForModel = true
            if !models.isActiveDownloaded {
                models.isPresented = true
            } else if case .failed = engine.phase {
                engine.load(models.activeSpec, from: models.directory(for: models.activeSpec))
            }
            return
        }
        isWaitingForModel = false
        player.stop()
        isHistoryExpanded = true
        generator.start(trimmedText, for: voice, style: style, speed: speed, store: store, engine: engine, player: player)
    }

    private func recognizeReference(_ voice: Voice) {
        Task {
            do {
                let heard = try await Transcriber.transcribe(store.fileURL(voice.sampleFileName))
                referenceDraft = heard
            } catch {
                localError = error.localizedDescription
            }
        }
    }

    private func cancelGeneration() {
        generator.cancel(voiceID)
        isWaitingForModel = false
    }
}

private struct ClipRow: View {
    @Environment(Player.self) private var player

    let clip: Clip
    let url: URL
    var onDelete: () -> Void
    var onReuse: () -> Void

    @State private var isHovered = false

    private var isPlaying: Bool { player.isPlaying(url) }

    var body: some View {
        HStack(spacing: 10) {
            PlayButton(isPlaying: isPlaying, size: 28) { player.toggle(url) }
            ClipWaveform(url: url).frame(width: 96, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.text).lineLimit(1)
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(Color.kpMuted)
            }
            Spacer()
            Button(action: export) {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1 : 0)
            .help("导出音频")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isPlaying ? Color.kpCyan.opacity(0.08) : .white.opacity(isHovered ? 0.05 : 0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isPlaying ? Color.kpCyan.opacity(0.35) : .white.opacity(isHovered ? 0.08 : 0.04))
        )
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.2), value: isPlaying)
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button("导出…", action: export)
            Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("再次编辑这段文字", action: onReuse)
            Divider()
            Button("删除", role: .destructive) {
                if player.isPlaying(url) { player.stop() }
                onDelete()
            }
        }
    }

    private var meta: String {
        [
            clip.createdAt.formatted(date: .omitted, time: .shortened),
            "\(Int(clip.duration.rounded())) 秒",
            clip.deliveryText,
            clip.modelName,
            clip.generationSeconds.map { "耗时 \(Int($0.rounded())) 秒" },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = String(clip.text.prefix(20)).replacingOccurrences(of: "/", with: "-") + ".wav"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: url, to: destination)
    }
}
