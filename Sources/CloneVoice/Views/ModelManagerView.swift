import AppKit
import SwiftUI

struct ModelManagerView: View {
    @Environment(ModelManager.self) private var models
    @Environment(VoiceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var deleting: ModelSpec?
    @State private var cleanupURLs: [URL] = []
    @State private var cleanupBytes: Int64 = 0
    @State private var notice: String?
    @State private var refreshToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(ModelCatalog.all) { spec in
                        ModelRow(spec: spec, onDelete: { deleting = spec })
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 580, height: 500)
        .onAppear(perform: refreshCleanup)
        .onChange(of: ModelCatalog.all.map { models.status(of: $0) == .downloaded }) { refreshCleanup() }
        .confirmationDialog(
            "删除「\(deleting?.name ?? "")」？",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("删除", role: .destructive) {
                guard let deleting else { return }
                models.delete(deleting)
                notice = "已删除 \(deleting.name)"
            }
        } message: {
            Text("会释放约 \(deleting.map { ModelManager.format(models.diskUsage(of: $0)) } ?? "")，需要时可以重新下载。已有的声音不受影响。")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("模型").font(.title3.weight(.semibold))
                Text("全部在本机运行，下载一次即可离线使用。切换模型不影响已保存的声音。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("模型共占用 \(ModelManager.format(models.totalModelBytes))")
                if let free = ModelManager.freeDiskBytes {
                    Text("磁盘剩余 \(ModelManager.format(free))")
                        .foregroundStyle(free < 3_000_000_000 ? Color.orange : Color.secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .id(refreshToken)

            Spacer()

            if let notice {
                Text(notice).font(.caption).foregroundStyle(.secondary).transition(.opacity)
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([ModelManager.root])
            } label: {
                Image(systemName: "folder")
            }
            .help("在访达中显示模型文件夹")
            Button(cleanupBytes > 0 ? "清理 \(ModelManager.format(cleanupBytes))" : "无需清理") {
                let freed = models.cleanup(cleanupURLs)
                notice = "已释放 \(ModelManager.format(freed))"
                refreshCleanup()
            }
            .disabled(cleanupBytes == 0)
            .help("删除下载缓存、未完成的下载、临时录音和不再使用的音频")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func refreshCleanup() {
        let referenced = Set(store.voices.flatMap { [$0.sampleFileName] + $0.clips.map(\.fileName) })
        cleanupURLs = models.cleanupCandidates(keeping: referenced, libraryRoot: store.rootURL)
        cleanupBytes = models.cleanupSize(cleanupURLs)
        refreshToken += 1
    }
}

private struct ModelRow: View {
    @Environment(ModelManager.self) private var models
    @Environment(VoiceEngine.self) private var engine

    let spec: ModelSpec
    var onDelete: () -> Void

    private var status: ModelManager.Status { models.status(of: spec) }
    private var isActive: Bool { models.activeID == spec.id }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(spec.name).font(.headline)
                    if spec.isRecommended { Badge(text: "推荐", color: .accentColor) }
                    if spec.supportsEmotionInstruction { Badge(text: "情绪指令", color: .purple) }
                }
                Text(spec.detail).font(.callout).foregroundStyle(.secondary)
                if case .failed(let message) = status {
                    Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(sizeLine).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 12)
            actions
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive && status == .downloaded ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isActive && status == .downloaded ? Color.accentColor.opacity(0.5) : .clear)
        )
    }

    private var sizeLine: String {
        status == .downloaded ? "已下载 · 占用 \(ModelManager.format(models.diskUsage(of: spec)))" : "大小约 \(spec.sizeText)"
    }

    @ViewBuilder
    private var actions: some View {
        switch status {
        case .notDownloaded:
            Button("下载") { models.download(spec) }
        case .failed:
            Button("重试") { models.download(spec) }
        case .downloading(let fraction):
            HStack(spacing: 8) {
                ProgressView(value: fraction).frame(width: 90)
                Text("\(Int(fraction * 100))%").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Button { models.cancelDownload(spec) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("取消下载")
            }
        case .downloaded:
            HStack(spacing: 8) {
                if isActive {
                    Label(engine.phase == .loading ? "加载中…" : "使用中", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.callout)
                } else {
                    Button("使用") { models.activate(spec) }
                }
                Menu {
                    Button("删除模型…", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}
