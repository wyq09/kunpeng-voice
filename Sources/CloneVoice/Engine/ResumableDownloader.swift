import Foundation

/// Downloads a Hugging Face repo file by file. Partial files survive network drops,
/// app restarts and cancellation, and resume with HTTP Range requests.
struct ResumableDownloader {
    struct RemoteFile {
        let path: String
        let size: Int64
    }

    enum Event {
        case progress(done: Int64, total: Int64)
        /// Connection dropped; waiting before attempt `attempt`.
        case retrying(attempt: Int, delay: Int)
    }

    static let hosts = [URL(string: "https://huggingface.co")!, URL(string: "https://hf-mirror.com")!]
    static let partialFolder = ".partial"
    private static let maxAttempts = 12

    let repo: String
    let patterns: [String]
    let destination: URL
    var onEvent: @Sendable (Event) async -> Void

    func run() async throws {
        let files = try await withRetries { host in try await listFiles(host: host) }
        let total = files.reduce(0) { $0 + $1.size }
        var finished = files.filter { isFinished($0) }.reduce(Int64(0)) { $0 + $1.size }
        await onEvent(.progress(done: finished + partialBytes(files), total: total))

        for file in files where !isFinished(file) {
            let base = finished
            try await withRetries { host in
                try await download(file, host: host) { written in
                    await onEvent(.progress(done: base + written, total: total))
                }
            }
            finished += file.size
        }
        try? FileManager.default.removeItem(at: destination.appendingPathComponent(Self.partialFolder))
    }

    /// Bytes already on disk from earlier attempts, for showing "继续下载 45%".
    static func resumableBytes(in destination: URL) -> Int64 {
        ModelManager.allocatedSize(of: destination.appendingPathComponent(partialFolder))
            + ((try? FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent != partialFolder }
            .reduce(0) { $0 + ModelManager.allocatedSize(of: $1) }
    }

    // MARK: - Retry

    /// Alternates between the official host and the mirror, backing off up to 30 s.
    private func withRetries<T>(_ body: (URL) async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                return try await body(Self.hosts[attempt % Self.hosts.count])
            } catch let error as DownloadError where !error.isRetryable {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                attempt += 1
                if attempt >= Self.maxAttempts { throw error }
                let delay = min(30, 1 << min(attempt, 5))
                await onEvent(.retrying(attempt: attempt, delay: delay))
                try await Task.sleep(for: .seconds(delay))
            }
        }
    }

    // MARK: - Listing

    private func listFiles(host: URL) async throws -> [RemoteFile] {
        let url = host.appendingPathComponent("api/models/\(repo)/tree/main")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "recursive", value: "true")]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        try Self.check(response)

        struct Entry: Decodable {
            struct LFS: Decodable { let size: Int64 }
            let type: String
            let path: String
            let size: Int64?
            let lfs: LFS?
        }
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        let files = entries
            .filter { $0.type == "file" && matches($0.path) }
            .map { RemoteFile(path: $0.path, size: $0.lfs?.size ?? $0.size ?? 0) }
        guard !files.isEmpty else { throw DownloadError.emptyRepo }
        return files
    }

    private func matches(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return patterns.contains { fnmatch($0, name, 0) == 0 || fnmatch($0, path, 0) == 0 }
    }

    // MARK: - Files

    private func finalURL(_ file: RemoteFile) -> URL { destination.appendingPathComponent(file.path) }

    private func partialURL(_ file: RemoteFile) -> URL {
        destination.appendingPathComponent(Self.partialFolder).appendingPathComponent(file.path + ".part")
    }

    private func isFinished(_ file: RemoteFile) -> Bool {
        Self.fileSize(finalURL(file)) == file.size
    }

    private func partialBytes(_ files: [RemoteFile]) -> Int64 {
        files.filter { !isFinished($0) }.reduce(0) { $0 + min(Self.fileSize(partialURL($1)) ?? 0, $1.size) }
    }

    private func download(
        _ file: RemoteFile,
        host: URL,
        onWritten: @escaping @Sendable (Int64) async -> Void
    ) async throws {
        let fm = FileManager.default
        let partial = partialURL(file)
        try fm.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: partial.path) { fm.createFile(atPath: partial.path, contents: nil) }

        var offset = Self.fileSize(partial) ?? 0
        if offset > file.size {
            try Data().write(to: partial)
            offset = 0
        }
        if offset < file.size || file.size == 0 {
            var request = URLRequest(url: host.appendingPathComponent("\(repo)/resolve/main/\(file.path)"))
            request.timeoutInterval = 60
            if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
            try await ChunkedTransfer(request: request, file: partial, resumeOffset: offset, onWritten: onWritten).run()
        }

        guard Self.fileSize(partial) == file.size else { throw DownloadError.incomplete }
        let target = finalURL(file)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: target)
        try fm.moveItem(at: partial, to: target)
    }

    static func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403, 404: throw DownloadError.http(http.statusCode, retryable: false)
        default: throw DownloadError.http(http.statusCode, retryable: true)
        }
    }

    enum DownloadError: Error {
        case http(Int, retryable: Bool)
        case emptyRepo
        case incomplete

        var isRetryable: Bool {
            switch self {
            case .http(_, let retryable): retryable
            case .emptyRepo: false
            case .incomplete: true
            }
        }
    }
}

/// Streams one HTTP response into a file, appending when the server honours the Range header.
private final class ChunkedTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let request: URLRequest
    private let fileURL: URL
    private let resumeOffset: Int64
    private let onWritten: @Sendable (Int64) async -> Void

    private var handle: FileHandle?
    private var written: Int64 = 0
    private var lastReport = Date.distantPast
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionDataTask?
    private let lock = NSLock()

    init(request: URLRequest, file: URL, resumeOffset: Int64, onWritten: @escaping @Sendable (Int64) async -> Void) {
        self.request = request
        self.fileURL = file
        self.resumeOffset = resumeOffset
        self.onWritten = onWritten
    }

    func run() async throws {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock { self.continuation = continuation }
                let task = session.dataTask(with: request)
                lock.withLock { self.task = task }
                task.resume()
            }
        } onCancel: {
            lock.withLock { task }?.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        do {
            try ResumableDownloader.check(response)
            let handle = try FileHandle(forWritingTo: fileURL)
            if (response as? HTTPURLResponse)?.statusCode == 206 {
                try handle.seekToEnd()
                written = resumeOffset
            } else {
                // Server ignored Range: start this file over.
                try handle.truncate(atOffset: 0)
                written = 0
            }
            self.handle = handle
            completionHandler(.allow)
        } catch {
            completionHandler(.cancel)
            finish(error)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try handle?.write(contentsOf: data)
            written += Int64(data.count)
            if Date().timeIntervalSince(lastReport) > 0.25 {
                lastReport = Date()
                let written = written
                let onWritten = onWritten
                Task { await onWritten(written) }
            }
        } catch {
            dataTask.cancel()
            finish(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
        if let error = error as? URLError, error.code == .cancelled {
            finish(CancellationError())
        } else {
            finish(error)
        }
    }

    private func finish(_ error: Error?) {
        let continuation = lock.withLock {
            let current = self.continuation
            self.continuation = nil
            return current
        }
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }
}
