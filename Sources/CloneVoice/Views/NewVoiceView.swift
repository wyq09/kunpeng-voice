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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 20)

                if let sampleURL {
                    review(sampleURL)
                } else if mode == .record {
                    recordStage
                } else {
                    uploadStage
                }

                footer
                    .padding(.top, 36)
            }
            .frame(maxWidth: 420)
            .padding(.vertical, 56)
            .frame(maxWidth: .infinity)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("新建声音").font(.system(size: 22, weight: .semibold))
            Text(subtitle).foregroundStyle(.secondary)
        }
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
            .padding(.top, 28)
            .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Text(Self.format(recorder.elapsed))
                .font(.system(size: 26, weight: .light, design: .rounded))
                .monospacedDigit()
                .padding(.top, 12)

            ProgressView(value: min(recorder.elapsed / Recorder.targetDuration, 1))
                .progressViewStyle(.linear)
                .tint(recorder.elapsed >= Recorder.targetDuration ? .green : .accentColor)
                .frame(width: 140)
                .padding(.top, 8)

            Text(recordHint)
                .font(.caption)
                .foregroundStyle(notice == nil ? .secondary : Color.orange)
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
                Text("朗读内容").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("换一段", action: nextPrompt)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .disabled(recorder.isRecording)
            }
            TextField("", text: $promptText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineSpacing(6)
                .disabled(recorder.isRecording)
        }
        .padding(14)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }

    private var uploadStage: some View {
        Button { isImporterPresented = true } label: {
            VStack(spacing: 10) {
                if isTranscribing {
                    ProgressView().controlSize(.small)
                    Text("正在识别音频里说的话…").foregroundStyle(.secondary)
                } else {
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("拖入音频文件，或点击选择").foregroundStyle(.primary)
                    Text("支持 WAV、MP3、M4A，超出 15 秒只取开头")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let notice {
                    Text(notice).font(.caption).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
            )
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
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(mode == .record ? "重录" : "换一个文件", action: resetSample)
                    .buttonStyle(.link)
            }
            .padding(14)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))

            if mode == .upload {
                VStack(alignment: .leading, spacing: 6) {
                    Text("音频里说的话").font(.caption).foregroundStyle(.secondary)
                    TextField("请填写音频里说的每一个字", text: $referenceText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Text(notice ?? "已自动识别，有错字改一下，克隆会更像。")
                        .font(.caption)
                        .foregroundStyle(notice == nil ? Color.secondary : Color.orange)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("名字").font(.caption).foregroundStyle(.secondary)
                TextField("比如：我自己", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
            }

            Button(action: save) {
                Text("保存声音").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
                .buttonStyle(.link)
            }
            Spacer()
            if let onCancel {
                Button("取消") {
                    recorder.discard()
                    onCancel()
                }
                .buttonStyle(.link)
            }
        }
        .font(.callout)
    }

    // MARK: - Actions

    private var canSave: Bool {
        let hasText = mode == .record || !referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.red.opacity(isRecording ? 0.25 : 0.12), lineWidth: 4)
                    .frame(width: 64, height: 64)
                    .scaleEffect(isRecording ? 1 + level * 0.35 : 1)
                    .animation(.easeOut(duration: 0.08), value: level)
                Circle()
                    .fill(.background)
                    .frame(width: 60, height: 60)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                RoundedRectangle(cornerRadius: isRecording ? 6 : 22)
                    .fill(Color.red)
                    .frame(width: isRecording ? 22 : 44, height: isRecording ? 22 : 44)
                    .animation(.spring(duration: 0.25), value: isRecording)
            }
            .frame(width: 88, height: 88)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isRecording ? "停止录音" : "开始录音")
    }
}

struct PlayButton: View {
    var isPlaying: Bool
    var size: CGFloat = 32
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.accentColor, in: Circle())
        }
        .buttonStyle(.plain)
        .help(isPlaying ? "停止" : "播放")
    }
}
