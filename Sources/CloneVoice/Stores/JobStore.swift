import Foundation
import Observation

/// One synthesis request from any process (app, MCP or command line), stored as its own file
/// so concurrent generators never contend for a shared file.
struct GenerationJob: Codable, Identifiable, Hashable {
    enum Source: String, Codable {
        case app, mcp, cli

        var title: String {
            switch self {
            case .app: "应用"
            case .mcp: "MCP"
            case .cli: "命令行"
            }
        }
    }

    enum Status: String, Codable {
        case loading, phrasing, generating, done, failed, cancelled
    }

    let id: UUID
    let source: Source
    let processID: Int32
    let voiceName: String
    var modelName: String
    let text: String
    let startedAt: Date
    var status: Status = .loading
    var current = 0
    var total = 0
    var finishedAt: Date?
    var outputPath: String?
    var audioDuration: TimeInterval?
    var message: String?

    var isRunning: Bool { [.loading, .phrasing, .generating].contains(status) }

    var progressText: String {
        switch status {
        case .loading: "正在加载模型"
        case .phrasing: "智能断句中"
        default: total > 1 ? "第 \(current)/\(total) 段" : "生成中"
        }
    }
    var outputURL: URL? { outputPath.map(URL.init(fileURLWithPath:)) }
    var elapsed: TimeInterval? { finishedAt.map { $0.timeIntervalSince(startedAt) } }
}

enum JobDirectory {
    static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CloneVoice/Jobs", isDirectory: true)

    static func fileURL(for id: UUID) -> URL { url.appendingPathComponent("\(id.uuidString).json") }
}

/// Writes the progress of one generation so every window and process can follow it.
@MainActor
final class JobRecorder {
    private(set) var job: GenerationJob

    init(source: GenerationJob.Source, voiceName: String, modelName: String, text: String) {
        job = GenerationJob(
            id: UUID(), source: source, processID: ProcessInfo.processInfo.processIdentifier,
            voiceName: voiceName, modelName: modelName, text: text, startedAt: .now)
        try? FileManager.default.createDirectory(at: JobDirectory.url, withIntermediateDirectories: true)
        save()
    }

    func modelReady(_ name: String) {
        job.modelName = name
        job.status = .phrasing
        save()
    }

    /// Mirrors `VoiceEngine.synthesize`'s progress callback.
    func progress(_ current: Int, _ total: Int) {
        if current == 0 {
            job.status = .phrasing
        } else {
            job.status = .generating
            job.current = current
            job.total = total
        }
        save()
    }

    func finish(output: URL, duration: TimeInterval, notice: String?) {
        job.status = .done
        job.current = job.total
        job.finishedAt = .now
        job.outputPath = output.path
        job.audioDuration = duration
        job.message = notice
        save()
    }

    func fail(_ error: Error) {
        job.finishedAt = .now
        if error is CancellationError {
            job.status = .cancelled
        } else {
            job.status = .failed
            job.message = error.localizedDescription
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(job) else { return }
        try? data.write(to: JobDirectory.fileURL(for: job.id), options: .atomic)
    }
}

/// Live list of all generations, refreshed whenever any process writes a job file.
@MainActor
@Observable
final class JobStore {
    private static let keepCount = 300

    private(set) var jobs: [GenerationJob] = []
    private var watcher: DispatchSourceFileSystemObject?
    private var refreshTask: Task<Void, Never>?
    private var isReloadPending = false

    var runningCount: Int { jobs.filter(\.isRunning).count }

    init() {
        try? FileManager.default.createDirectory(at: JobDirectory.url, withIntermediateDirectories: true)
        reload()
        prune()
        watch()
    }

    func delete(_ job: GenerationJob) {
        try? FileManager.default.removeItem(at: JobDirectory.fileURL(for: job.id))
        reload()
    }

    func clearFinished() {
        for job in jobs where !job.isRunning { try? FileManager.default.removeItem(at: JobDirectory.fileURL(for: job.id)) }
        reload()
    }

    private func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: JobDirectory.url, includingPropertiesForKeys: nil)) ?? []
        jobs = files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(GenerationJob.self, from: Data(contentsOf: $0)) }
            .map(Self.markingAbandoned)
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// A job whose process is gone will never finish.
    private static func markingAbandoned(_ job: GenerationJob) -> GenerationJob {
        guard job.isRunning, kill(job.processID, 0) != 0 else { return job }
        var job = job
        job.status = .failed
        job.message = "生成进程已退出，没有完成"
        return job
    }

    private func prune() {
        for job in jobs.dropFirst(Self.keepCount) where !job.isRunning {
            try? FileManager.default.removeItem(at: JobDirectory.fileURL(for: job.id))
        }
    }

    private func watch() {
        let descriptor = open(JobDirectory.url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
        // Catches jobs from processes that died without a final write.
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.runningCount > 0 else { continue }
                self.reload()
            }
        }
    }

    /// Progress writes arrive in bursts; read the directory once per burst.
    private func scheduleReload() {
        guard !isReloadPending else { return }
        isReloadPending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            self?.isReloadPending = false
            self?.reload()
        }
    }
}
