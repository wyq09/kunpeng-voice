import Foundation
import HuggingFace
import Observation

@MainActor
@Observable
final class ModelManager {
    enum Status: Equatable {
        case notDownloaded
        case downloading(Double)
        case downloaded
        case failed(String)
    }

    static let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CloneVoice/Models", isDirectory: true)
    private static let hubCacheRoot = root.appendingPathComponent(".hub", isDirectory: true)
    private static let activeKey = "activeModelID"

    private(set) var statuses: [ModelSpec.ID: Status] = [:]
    /// Transient hint while a download is reconnecting.
    private(set) var downloadNotes: [ModelSpec.ID: String] = [:]
    private(set) var activeID: ModelSpec.ID
    var isPresented = false
    private var tasks: [ModelSpec.ID: Task<Void, Never>] = [:]

    var activeSpec: ModelSpec { ModelCatalog.spec(id: activeID) ?? ModelCatalog.defaultModel }
    var isActiveDownloaded: Bool { status(of: activeSpec) == .downloaded }

    init() {
        try? FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
        Self.migrateLegacyLayout()

        let stored = UserDefaults.standard.string(forKey: Self.activeKey).flatMap(ModelCatalog.spec(id:))
        let firstDownloaded = ModelCatalog.all.first { Self.isComplete($0) }
        activeID = (stored ?? firstDownloaded ?? ModelCatalog.defaultModel).id
        for spec in ModelCatalog.all {
            statuses[spec.id] = Self.isComplete(spec) ? .downloaded : .notDownloaded
        }
    }

    func status(of spec: ModelSpec) -> Status { statuses[spec.id] ?? .notDownloaded }

    func directory(for spec: ModelSpec) -> URL { Self.root.appendingPathComponent(spec.folderName, isDirectory: true) }

    func activate(_ spec: ModelSpec) {
        activeID = spec.id
        UserDefaults.standard.set(spec.id, forKey: Self.activeKey)
    }

    /// First launch: nothing on disk yet, so fetch the default without asking.
    func downloadActiveIfNothingInstalled() {
        guard !statuses.values.contains(.downloaded), tasks.isEmpty else { return }
        download(activeSpec)
    }

    func download(_ spec: ModelSpec) {
        guard tasks[spec.id] == nil else { return }
        let needed = spec.sizeBytes + 300_000_000
        if let free = Self.freeDiskBytes, free < needed {
            statuses[spec.id] = .failed("磁盘空间不足，还差 \(Self.format(needed - free))。删掉不用的模型或点「清理」后再试。")
            return
        }

        statuses[spec.id] = .downloading(0)
        tasks[spec.id] = Task {
            defer { tasks[spec.id] = nil }
            do {
                try await fetch(spec)
                statuses[spec.id] = .downloaded
                if !isActiveDownloaded { activate(spec) }
            } catch is CancellationError {
                statuses[spec.id] = .notDownloaded
            } catch {
                downloadNotes[spec.id] = nil
                guard !Task.isCancelled else {
                    statuses[spec.id] = .notDownloaded
                    return
                }
                let saved = resumableFraction(of: spec).map { "已保存 \(Int($0 * 100))% 的进度，" } ?? ""
                statuses[spec.id] = .failed("网络一直连不上，\(saved)检查网络后点「继续下载」接着下。")
            }
        }
    }

    /// Stops the transfer but keeps what has been downloaded so far.
    func cancelDownload(_ spec: ModelSpec) {
        tasks[spec.id]?.cancel()
        tasks[spec.id] = nil
        downloadNotes[spec.id] = nil
        statuses[spec.id] = .notDownloaded
    }

    func delete(_ spec: ModelSpec) {
        cancelDownload(spec)
        try? FileManager.default.removeItem(at: directory(for: spec))
        removeHubCache(for: spec)
        statuses[spec.id] = .notDownloaded
        if spec.id == activeID, let fallback = ModelCatalog.all.first(where: { status(of: $0) == .downloaded }) {
            activate(fallback)
        }
    }

    func discardPartialDownload(_ spec: ModelSpec) {
        guard status(of: spec) != .downloaded else { return }
        cancelDownload(spec)
        try? FileManager.default.removeItem(at: directory(for: spec))
    }

    func diskUsage(of spec: ModelSpec) -> Int64 { Self.allocatedSize(of: directory(for: spec)) }

    var totalModelBytes: Int64 {
        ModelCatalog.all.filter { status(of: $0) == .downloaded }.reduce(0) { $0 + diskUsage(of: $1) }
    }

    // MARK: - Cleanup

    /// Download caches, unfinished downloads, temp recordings and audio no voice references anymore.
    func cleanupCandidates(keeping referencedFiles: Set<String>, libraryRoot: URL) -> [URL] {
        let fileManager = FileManager.default
        var urls: [URL] = []

        let knownFolders = Set(ModelCatalog.all.map(\.folderName))
        let downloading = Set(tasks.keys.compactMap(ModelCatalog.spec(id:)).map(\.folderName))
        for url in (try? fileManager.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: nil)) ?? [] {
            let name = url.lastPathComponent
            if downloading.contains(name) { continue }
            if name == ".hub" {
                if tasks.isEmpty { urls.append(url) }
            } else if !knownFolders.contains(name) {
                urls.append(url)
            }
        }

        let temp = fileManager.temporaryDirectory
        for url in (try? fileManager.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)) ?? [] {
            let name = url.lastPathComponent
            if name.hasPrefix("recording-") || name.hasPrefix("upload-") || name.hasPrefix("CFNetworkDownload_") {
                urls.append(url)
            }
        }

        let legacySpeechCache = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("qwen3-speech")
        if fileManager.fileExists(atPath: legacySpeechCache.path) { urls.append(legacySpeechCache) }

        for url in (try? fileManager.contentsOfDirectory(at: libraryRoot, includingPropertiesForKeys: nil)) ?? []
        where url.pathExtension == "wav" || url.pathExtension == "m4a" || url.pathExtension == "mp3" {
            if !referencedFiles.contains(url.lastPathComponent) { urls.append(url) }
        }
        return urls
    }

    func cleanupSize(_ urls: [URL]) -> Int64 { urls.reduce(0) { $0 + Self.allocatedSize(of: $1) } }

    func cleanup(_ urls: [URL]) -> Int64 {
        let freed = cleanupSize(urls)
        urls.forEach { try? FileManager.default.removeItem(at: $0) }
        return freed
    }

    // MARK: - Download

    private func fetch(_ spec: ModelSpec) async throws {
        let fileManager = FileManager.default
        let destination = directory(for: spec)
        try? fileManager.removeItem(at: destination.appendingPathComponent(".complete"))
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let downloader = ResumableDownloader(
            repo: spec.id,
            patterns: spec.downloadPatterns,
            destination: destination
        ) { [weak self] event in
            await self?.handle(event, for: spec)
        }
        try await downloader.run()
        try Task.checkCancellation()
        fileManager.createFile(atPath: destination.appendingPathComponent(".complete").path, contents: nil)
        removeHubCache(for: spec)
    }

    private func handle(_ event: ResumableDownloader.Event, for spec: ModelSpec) {
        guard tasks[spec.id] != nil else { return }
        switch event {
        case .progress(let done, let total):
            statuses[spec.id] = .downloading(total > 0 ? Double(done) / Double(total) : 0)
            downloadNotes[spec.id] = nil
        case .retrying(let attempt, let delay):
            downloadNotes[spec.id] = "网络断了，\(delay) 秒后自动重连（第 \(attempt) 次），已下载的部分不会丢"
        }
    }

    /// Share of an unfinished download already on disk, so the UI can offer "继续下载".
    func resumableFraction(of spec: ModelSpec) -> Double? {
        guard status(of: spec) != .downloaded, spec.sizeBytes > 0 else { return nil }
        let bytes = ResumableDownloader.resumableBytes(in: directory(for: spec))
        guard bytes > 1_000_000 else { return nil }
        return min(0.99, Double(bytes) / Double(spec.sizeBytes))
    }

    private func removeHubCache(for spec: ModelSpec) {
        guard let repoID = Repo.ID(rawValue: spec.id) else { return }
        let cache = HubCache(cacheDirectory: Self.hubCacheRoot)
        try? FileManager.default.removeItem(at: cache.repoDirectory(repo: repoID, kind: .model))
    }

    // MARK: - Helpers

    private static func isComplete(_ spec: ModelSpec) -> Bool {
        FileManager.default.fileExists(
            atPath: root.appendingPathComponent(spec.folderName).appendingPathComponent(".complete").path
        )
    }

    /// v1 stored Qwen3 under `Models/mlx-audio/<repo>`.
    private static func migrateLegacyLayout() {
        let fileManager = FileManager.default
        let legacyRoot = root.appendingPathComponent("mlx-audio")
        for url in (try? fileManager.contentsOfDirectory(at: legacyRoot, includingPropertiesForKeys: nil)) ?? [] {
            let target = root.appendingPathComponent(url.lastPathComponent)
            guard fileManager.fileExists(atPath: url.appendingPathComponent(".complete").path),
                  !fileManager.fileExists(atPath: target.path)
            else { continue }
            try? fileManager.moveItem(at: url, to: target)
        }
        for url in (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        where url.lastPathComponent.hasPrefix("models--") {
            try? fileManager.removeItem(at: url)
        }
    }

    static var freeDiskBytes: Int64? {
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    nonisolated static func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        guard isDirectory.boolValue else {
            return Int64((try? url.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let file = enumerator?.nextObject() as? URL {
            let values = try? file.resourceValues(forKeys: keys)
            if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
