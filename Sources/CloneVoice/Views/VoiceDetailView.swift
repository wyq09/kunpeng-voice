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

    let voiceID: Voice.ID
    var onDeleted: () -> Void

    @AppStorage("speechStyle") private var style: SpeechStyle = .natural
    @AppStorage("speechSpeed") private var speed: SpeechSpeed = .normal

    @State private var text = ""
    @State private var textSelection: TextSelection?
    @State private var name = ""
    @State private var isWaitingForModel = false
    @State private var generation: Task<Void, Never>?
    @State private var progress: (current: Int, total: Int)?
    @State private var startedAt: Date?
    @State private var errorMessage: String?
    @State private var isConfirmingDelete = false
    @State private var referenceDraft: String?
    @State private var isHistoryExpanded = true
    @FocusState private var isEditorFocused: Bool

    private var voice: Voice? { store.voice(id: voiceID) }
    private var isBusy: Bool { generation != nil }
    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        if let voice {
            VStack(spacing: 0) {
                header(voice)
                editor
                if !voice.clips.isEmpty { history(voice) }
                Divider()
                toolbar
            }
            .onAppear {
                name = voice.name
                isEditorFocused = true
            }
            .onDisappear {
                store.rename(voiceID, to: name)
                generation?.cancel()
                player.stop()
            }
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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("名字", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .semibold))
                    .onSubmit { store.rename(voiceID, to: name) }
                    .help("点击修改名字")
                Button { referenceDraft = voice.referenceText } label: {
                    Text("参考录音「\(voice.referenceText)」")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("点击校对：要和录音里说的一字不差，否则可能多读或漏读")
            }
            Spacer(minLength: 12)
            let sampleURL = store.fileURL(voice.sampleFileName)
            Button {
                player.toggle(sampleURL)
            } label: {
                Image(systemName: player.isPlaying(sampleURL) ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
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
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
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
                        .foregroundStyle(.tertiary)
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
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
    }

    private var editorFooter: some View {
        HStack(spacing: 8) {
            scriptSummary
            Spacer(minLength: 8)
            Button { phrasing.isPresented = true } label: {
                Label(phrasing.summary, systemImage: phrasing.config.isUsable ? "text.word.spacing" : "text.alignleft")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(phrasing.config.isUsable ? Color.accentColor : .secondary)
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
        .foregroundStyle(.secondary)
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
                .foregroundStyle(script.unknownTags.isEmpty ? Color.secondary : Color.orange)
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
            Divider()
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
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isHistoryExpanded {
                ScrollView {
                    LazyVStack(spacing: 0) {
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
                    .padding(.horizontal, 8)
                }
                .frame(maxHeight: 190)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            StylePicker(
                selection: $style,
                isApproximate: !(engine.loadedSpec ?? models.activeSpec).supportsEmotionInstruction,
                onOpenModels: { models.isPresented = true }
            )
            Picker("语速", selection: $speed) {
                ForEach(SpeechSpeed.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("语速")

            statusLine
                .frame(maxWidth: .infinity, alignment: .trailing)

            if isBusy {
                Button("停止", action: cancelGeneration)
            }
            Button(action: startGeneration) {
                Text(isBusy ? "生成中…" : "生成").frame(minWidth: 56)
            }
            .buttonStyle(.borderedProminent)
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
                    .foregroundStyle(.orange)
                    .help(errorMessage)
            } else if isWaitingForModel {
                Label("模型准备好后自动生成", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            } else if let progress, let startedAt {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        let seconds = Int(context.date.timeIntervalSince(startedAt))
                        Text(progress.current == 0 ? "智能断句中 · \(seconds) 秒"
                            : progress.total > 1 ? "第 \(progress.current)/\(progress.total) 段 · \(seconds) 秒"
                            : "生成中 · \(seconds) 秒")
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(.secondary)
            } else if !trimmedText.isEmpty {
                Text("\(trimmedText.count) 字").foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .lineLimit(1)
    }

    // MARK: - Actions

    private func startGeneration() {
        guard !trimmedText.isEmpty, generation == nil, let voice else { return }
        errorMessage = nil
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

        let input = trimmedText
        let style = style
        let speed = speed
        let modelName = engine.loadedSpec?.name ?? models.activeSpec.name
        let started = Date.now
        startedAt = started
        progress = (1, 1)
        generation = Task {
            let recorder = JobRecorder(source: .app, voiceName: voice.name, modelName: modelName, text: input)
            recorder.modelReady(modelName)
            defer {
                generation = nil
                progress = nil
                startedAt = nil
            }
            do {
                let result = try await engine.synthesize(
                    text: input,
                    sampleURL: store.fileURL(voice.sampleFileName),
                    referenceText: voice.referenceText,
                    language: voice.primaryLanguage,
                    style: style,
                    speed: speed
                ) { current, total in
                    progress = (current, total)
                    recorder.progress(current, total)
                }
                try Task.checkCancellation()

                let fileName = "\(UUID().uuidString).wav"
                let url = store.fileURL(fileName)
                try AudioUtils.writeWavFile(samples: result.samples, sampleRate: result.sampleRate, fileURL: url)
                recorder.finish(output: url, duration: Double(result.samples.count) / Double(result.sampleRate), notice: result.notice)
                errorMessage = result.notice
                if let clip = store.addClip(
                    to: voiceID, text: input, fileName: fileName, style: style, speed: speed,
                    modelName: modelName, generationSeconds: Date.now.timeIntervalSince(started)
                ) {
                    isHistoryExpanded = true
                    player.toggle(store.fileURL(clip.fileName))
                }
            } catch is CancellationError {
                recorder.fail(CancellationError())
            } catch let error as EngineError {
                recorder.fail(error)
                errorMessage = error.errorDescription
            } catch {
                recorder.fail(error)
                errorMessage = "生成失败，改短一点再试试"
            }
        }
    }

    private func recognizeReference(_ voice: Voice) {
        Task {
            do {
                let heard = try await Transcriber.transcribe(store.fileURL(voice.sampleFileName))
                referenceDraft = heard
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelGeneration() {
        generation?.cancel()
        generation = nil
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

    var body: some View {
        HStack(spacing: 10) {
            PlayButton(isPlaying: player.isPlaying(url), size: 26) { player.toggle(url) }
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.text).lineLimit(1)
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: export) {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1 : 0)
            .help("导出音频")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isHovered ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
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
