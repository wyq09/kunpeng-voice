import AppKit
import SwiftUI

/// Every generation from the app, MCP and the command line, with live progress.
struct JobsSheet: View {
    @Environment(JobStore.self) private var jobs
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("生成任务").font(.system(size: 17, weight: .semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if jobs.jobs.contains(where: { !$0.isRunning }) {
                    Button("清除已结束", action: jobs.clearFinished)
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .help("只删记录，不删音频文件")
                }
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)
            Divider()

            if jobs.jobs.isEmpty {
                ContentUnavailableView(
                    "还没有生成任务",
                    systemImage: "waveform.badge.plus",
                    description: Text("在应用里生成，或让 Agent 通过 MCP、命令行调用，都会在这里实时显示进度。")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(jobs.jobs) { job in
                            JobRow(job: job)
                            Divider().padding(.leading, 56)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 720, height: 560)
    }

    private var subtitle: String {
        let running = jobs.runningCount
        return running > 0 ? "\(running) 条正在生成 · 共 \(jobs.jobs.count) 条" : "共 \(jobs.jobs.count) 条"
    }
}

private struct JobRow: View {
    @Environment(JobStore.self) private var jobs
    @Environment(Player.self) private var player

    let job: GenerationJob
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leading.frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 5) {
                Text(job.text)
                    .lineLimit(2)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Tag(text: job.source.title, color: job.source == .app ? .secondary : .purple)
                    Label(job.voiceName, systemImage: "person.wave.2")
                    Label(job.modelName, systemImage: "cpu")
                    Text(job.startedAt.formatted(.dateTime.month().day().hour().minute()))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                status
            }
            Spacer(minLength: 8)
            if let url = job.outputURL, job.status == .done {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .opacity(isHovered ? 1 : 0)
                .help("在访达中显示")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(isHovered ? Color.primary.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            if let url = job.outputURL, job.status == .done {
                Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            Button("复制文字") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(job.text, forType: .string)
            }
            if !job.isRunning {
                Divider()
                Button("删除记录", role: .destructive) { jobs.delete(job) }
            }
        }
    }

    @ViewBuilder
    private var leading: some View {
        if let url = job.outputURL, job.status == .done, FileManager.default.fileExists(atPath: url.path) {
            PlayButton(isPlaying: player.isPlaying(url), size: 26) { player.toggle(url) }
        } else if job.isRunning {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: job.status == .cancelled ? "stop.circle" : "exclamationmark.circle")
                .font(.system(size: 18))
                .foregroundStyle(job.status == .cancelled ? Color.secondary : Color.orange)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch job.status {
        case .loading, .phrasing, .generating:
            TimelineView(.periodic(from: job.startedAt, by: 1)) { context in
                let seconds = Int(context.date.timeIntervalSince(job.startedAt))
                VStack(alignment: .leading, spacing: 4) {
                    if job.status == .generating, job.total > 0 {
                        ProgressView(value: Double(job.current - 1), total: Double(job.total))
                            .controlSize(.small)
                            .frame(maxWidth: 320)
                    }
                    Text("\(job.progressText) · 已用 \(seconds) 秒")
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .done:
            Text(doneText)
                .font(.caption)
                .foregroundStyle(job.message == nil ? Color.secondary : Color.orange)
        case .failed:
            Text(job.message ?? "生成失败").font(.caption).foregroundStyle(.orange)
        case .cancelled:
            Text("已停止").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var doneText: String {
        [
            job.audioDuration.map { "音频 \(Int($0.rounded())) 秒" },
            job.elapsed.map { "耗时 \(Int($0.rounded())) 秒" },
            job.message,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

/// An agent's generation of this voice, shown in the voice's history while it runs.
struct RunningJobRow: View {
    let job: GenerationJob

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.text).lineLimit(1)
                TimelineView(.periodic(from: job.startedAt, by: 1)) { context in
                    let seconds = Int(context.date.timeIntervalSince(job.startedAt))
                    Text("\(job.source.title) · \(job.modelName) · \(job.progressText) · \(seconds) 秒")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

private struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}
