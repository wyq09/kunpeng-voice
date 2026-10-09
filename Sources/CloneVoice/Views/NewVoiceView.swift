import SwiftUI
import UniformTypeIdentifiers

struct NewVoiceView: View {
    @Environment(VoiceStore.self) private var store
    @Environment(Player.self) private var player

    var onCreated: (Voice) -> Void
    var onCancel: (() -> Void)?

    private enum Mode { case record, upload }

    @State private var mode: Mode = .record
    @State private var recorder = Recorder()
    @State private var promptIndex = 0
    @State private var promptText = Self.prompts[0]

    @State private var sampleURL: URL?
    @State private var referenceText = ""
    @State private var name = ""
    @State private var isTranscribing = false
    @State private var isDropTargeted = false
    @State private var isImporterPresented = false
    @State private var notice: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, 16)

                    if let sampleURL {
                        review(sampleURL)
                    } else if mode == .record {
                        recordStage
                    } else {
                        uploadStage
                    }
                }
                .frame(maxWidth: 420)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
            }

            footer
                .padding(.horizontal, 4)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
                .background {
                    LinearGradient(
                        colors: [Color.kpBackground.opacity(0), Color.kpBackground.opacity(0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
        }
        .onDisappear {
            recorder.stop()
            player.stop()
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { importAudio(url) }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 6) {
            KunpengParticles(energy: recorder.isRecording ? recorder.level : 0)
                .frame(width: 176, height: 176)
            .help("移动鼠标拨动羽翼，点击让鲲鹏发声")
            Text("创建声音")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.kpTitle)
            Text(subtitle).foregroundStyle(Color.kpMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var subtitle: String {
        if sampleURL != nil { return "听一下效果，满意就给它起个名字。" }
        return mode == .record ? "照着下面这段话念一遍，大约 10 秒。" : "选一段只有你说话的音频，10～15 秒最好。"
    }

    private var recordStage: some View {
        VStack(spacing: 0) {
            promptCard
            Text("可以改成你想念的话，念的内容要和这里一字不差。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .padding(.horizontal, 2)

            RecordButton(isRecording: recorder.isRecording, level: recorder.level) {
                toggleRecording()
            }
            .padding(.top, 24)
            .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            LevelWave(level: recorder.level, isActive: recorder.isRecording)
                .frame(width: 240, height: 34)
                .padding(.top, 10)
                .opacity(recorder.isRecording ? 1 : 0.35)

            Text(Self.format(recorder.elapsed))
                .font(.system(size: 26, weight: .light, design: .rounded))
                .monospacedDigit()
                .padding(.top, 6)

            KPProgressBar(
                value: recorder.elapsed / Recorder.targetDuration,
                isComplete: recorder.elapsed >= Recorder.targetDuration
            )
            .frame(width: 160)
            .padding(.top, 8)

            Text(recordHint)
                .font(.caption)
                .foregroundStyle(notice == nil ? Color.kpMuted : Color.kpGold)
                .padding(.top, 10)
        }
    }

    private var recordHint: String {
        if recorder.isPermissionDenied { return "没有麦克风权限：系统设置 → 隐私与安全性 → 麦克风，打开后再试" }
        if let notice { return notice }
        if recorder.isRecording {
            return recorder.elapsed >= Recorder.targetDuration ? "够了，念完这句就可以点停止" : "正在录音，念完再点一下"
        }
        return "点一下开始，念完再点一下"
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("朗读内容", systemImage: "text.quote").font(.caption).foregroundStyle(Color.kpMuted)
                Spacer()
                Button("换一段", action: nextPrompt)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.kpCyan)
                    .disabled(recorder.isRecording)
            }
            TextField("", text: $promptText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineSpacing(6)
                .disabled(recorder.isRecording)
        }
        .padding(16)
        .kpPanel(cornerRadius: 14, isHighlighted: recorder.isRecording)
        .animation(.easeOut(duration: 0.3), value: recorder.isRecording)
    }

    private var uploadStage: some View {
        Button { isImporterPresented = true } label: {
            VStack(spacing: 10) {
                if isTranscribing {
                    ProgressView().controlSize(.small)
                    Text("正在识别音频里说的话…").foregroundStyle(.secondary)
                } else {
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 30))
                        .foregroundStyle(.kpPrimary)
                        .shadow(color: .kpCyan.opacity(0.5), radius: 8)
                    Text("拖入音频文件，或点击选择").foregroundStyle(.primary)
                    Text("支持 WAV、MP3、M4A，超出 15 秒只取开头")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let notice {
                    Text(notice).font(.caption).foregroundStyle(Color.kpGold)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.kpCyan.opacity(isDropTargeted ? 0.1 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle(isDropTargeted ? Color.kpCyan : Color.kpLineStrong)
            )
            .shadow(color: .kpCyan.opacity(isDropTargeted ? 0.3 : 0), radius: 16)
            .animation(.easeOut(duration: 0.2), value: isDropTargeted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isTranscribing)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in importAudio(url) } }
            }
            return true
        }
    }

    private func review(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                PlayButton(isPlaying: player.isPlaying(url)) { player.toggle(url) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("你的声音样本")
                    Text("\(Int(VoiceStore.duration(of: url).rounded())) 秒")
                        .font(.caption)
                        .foregroundStyle(Color.kpMuted)
                }
                ClipWaveform(url: url).frame(height: 28)
                Button(mode == .record ? "重录" : "换一个文件", action: resetSample)
                    .buttonStyle(.kpGhost)
            }
            .padding(14)
            .kpPanel(cornerRadius: 14, isHighlighted: player.isPlaying(url))

            VStack(alignment: .leading, spacing: 6) {
                Text("音频里说的话").font(.caption).foregroundStyle(Color.kpMuted)
                TextField("请填写音频里说的每一个字", text: $referenceText, axis: .vertical)
                    .textFieldStyle(.kp)
                    .disabled(isTranscribing)
                Text(notice ?? (isTranscribing ? "正在核对你实际说的话…" : "已按录音自动识别，和录音一字不差时克隆最像，有错字改一下。"))
                    .font(.caption)
                    .foregroundStyle(notice == nil ? Color.kpMuted : Color.kpGold)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("名字").font(.caption).foregroundStyle(Color.kpMuted)
                TextField("比如：我自己", text: $name)
                    .textFieldStyle(.kp)
                    .onSubmit(save)
            }

            Button(action: save) {
                Text("保存声音").frame(maxWidth: .infinity)
            }
            .buttonStyle(.kpPrimaryLarge)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
    }

    private var footer: some View {
        HStack {
            if sampleURL == nil, !recorder.isRecording {
                Button(mode == .record ? "改为上传音频文件" : "改为现场录音") {
                    notice = nil
                    mode = mode == .record ? .upload : .record
                }
                .buttonStyle(.plain).foregroundStyle(Color.kpCyan)
            }
            Spacer()
            if let onCancel {
                Button("取消") {
                    recorder.discard()
                    onCancel()
                }
                .buttonStyle(.plain).foregroundStyle(Color.kpCyan)
            }
        }
        .font(.callout)
    }

    // MARK: - Actions

    private var canSave: Bool {
        let hasText = !referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText && !isTranscribing
    }

    private func toggleRecording() {
        notice = nil
        guard recorder.isRecording else {
            player.stop()
            Task { await recorder.start() }
            return
        }
        recorder.stop()
        guard recorder.elapsed >= Recorder.minDuration, let url = recorder.fileURL else {
            recorder.discard()
            notice = "太短了，至少念 \(Int(Recorder.minDuration)) 秒，再录一次"
            return
        }
        referenceText = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        name = defaultName
        sampleURL = url

        // People rarely read the prompt verbatim; a mismatched transcript makes the clone leak or skip words.
        isTranscribing = true
        Task {
            defer { isTranscribing = false }
            if let heard = try? await Transcriber.transcribe(url),
               !heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                referenceText = heard
            }
        }
    }

    private func importAudio(_ url: URL) {
        notice = nil
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }

        guard let prepared = try? SampleTrimmer.prepare(url) else {
            notice = "这个文件读不了，换一个 WAV / MP3 / M4A 试试"
            return
        }
        guard VoiceStore.duration(of: prepared) >= Recorder.minDuration else {
            notice = "音频太短了，至少需要 \(Int(Recorder.minDuration)) 秒"
            return
        }

        isTranscribing = true
        Task {
            defer { isTranscribing = false }
            do {
                referenceText = try await Transcriber.transcribe(prepared)
            } catch {
                referenceText = ""
                notice = error.localizedDescription
            }
            name = url.deletingPathExtension().lastPathComponent
            sampleURL = prepared
        }
    }

    private func resetSample() {
        player.stop()
        if mode == .record { recorder.discard() }
        sampleURL = nil
        notice = nil
        if mode == .upload { isImporterPresented = true }
    }

    private func save() {
        guard canSave, let sampleURL else { return }
        player.stop()
        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let voice = try store.addVoice(
                name: finalName.isEmpty ? defaultName : finalName,
                sampleURL: sampleURL,
                referenceText: referenceText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onCreated(voice)
        } catch {
            notice = "保存失败：\(error.localizedDescription)"
        }
    }

    private func nextPrompt() {
        promptIndex = (promptIndex + 1) % Self.prompts.count
        promptText = Self.prompts[promptIndex]
    }

    private var defaultName: String {
        store.voices.isEmpty ? "我的声音" : "我的声音 \(store.voices.count + 1)"
    }

    static func format(_ time: TimeInterval) -> String {
        let seconds = Int(time)
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private static let prompts = [
        "今天天气不错，我想用自己的声音录一段话。希望克隆出来的效果自然、清楚，听起来就像我本人在说话。",
        "早上出门的时候，楼下的咖啡店刚刚开门。我点了一杯热拿铁，坐在窗边看着街上的行人，心情一下子就好了起来。",
        "如果你正在听这段话，说明一切都很顺利。接下来我会用平常说话的语气，把想说的内容慢慢讲给你听。",
        "周末我喜欢去公园散步，看看湖边的树和天上的云。有时候什么都不想，就这样安安静静地待一会儿，也挺好的。",
    ]
}

// MARK: - Components

private struct RecordButton: View {
    var isRecording: Bool
    var level: Double
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRecording {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        ZStack {
                            ForEach(0..<3, id: \.self) { ring in
                                let progress = (t * 0.6 + Double(ring) / 3).truncatingRemainder(dividingBy: 1)
                                Circle()
                                    .stroke(ring == 1 ? Color.kpGold : .kpCoral, lineWidth: 1.2)
                                    .frame(width: 64, height: 64)
                                    .scaleEffect(1 + progress * (0.7 + level * 0.9))
                                    .opacity((1 - progress) * 0.7)
                            }
                        }
                    }
                }
                Circle()
                    .fill(RadialGradient(
                        colors: [(isRecording ? Color.kpCoral : .kpCyan).opacity(0.35), .clear],
                        center: .center, startRadius: 20, endRadius: 50
                    ))
                    .frame(width: 100, height: 100)
                    .scaleEffect(isRecording ? 1 + level * 0.35 : (isHovered ? 1.08 : 1))
                    .animation(.easeOut(duration: 0.08), value: level)
                Circle()
                    .fill(Color.kpBackground2)
                    .frame(width: 64, height: 64)
                    .overlay(Circle().strokeBorder(
                        AngularGradient(colors: [.kpCyan, .kpGold, .kpTeal, .kpCyan], center: .center),
                        lineWidth: 1.5
                    ))
                    .shadow(color: .kpCyan.opacity(0.35), radius: 10)
                RoundedRectangle(cornerRadius: isRecording ? 6 : 22, style: .continuous)
                    .fill(isRecording
                        ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.55, blue: 0.5), .kpCoral], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(.kpPrimary))
                    .frame(width: isRecording ? 22 : 44, height: isRecording ? 22 : 44)
                    .overlay {
                        if !isRecording {
                            Image(systemName: "mic.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.kpInk)
                        }
                    }
                    .animation(.spring(duration: 0.3), value: isRecording)
            }
            .frame(width: 110, height: 110)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .help(isRecording ? "停止录音" : "开始录音")
    }
}
