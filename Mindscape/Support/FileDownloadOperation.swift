import CryptoKit
import Foundation

/// `URLSessionDownloadTask` 的 async/await 包装，带进度回调与取消。
/// 回调固定在主队列，进度闭包里再切回 MainActor。
final class FileDownloadOperation: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let configuration: URLSessionConfiguration
    private let progressHandler: @Sendable (Int64, Int64) -> Void

    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var responseError: Error?
    private var writeError: Error?
    private var lastReportedProgress: Double = -1

    init(
        destination: URL,
        configuration: URLSessionConfiguration = .ephemeral,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) {
        self.destination = destination
        self.configuration = configuration
        self.progressHandler = progress
    }

    func start(with request: URLRequest) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
            self.session = session

            let task = session.downloadTask(with: request)
            self.task = task
            task.resume()
        }
    }

    func cancel() {
        task?.cancel()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // 下载回调可能非常密集；这里按 1% 节流，避免每来一块数据就创建 MainActor Task。
        let expected = totalBytesExpectedToWrite
        let progress = expected > 0 ? Double(totalBytesWritten) / Double(expected) : 0
        guard progress - lastReportedProgress >= 0.01 || progress >= 1 else { return }
        lastReportedProgress = progress
        progressHandler(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            responseError = UpdateServiceError.httpStatus(http.statusCode)
            return
        }

        do {
            let fileManager = FileManager.default
            try? fileManager.removeItem(at: destination)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: location, to: destination)
        } catch {
            writeError = error
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        self.session?.finishTasksAndInvalidate()
        self.session = nil

        guard let continuation else { return }
        self.continuation = nil

        if let error {
            continuation.resume(throwing: error)
        } else if let responseError {
            continuation.resume(throwing: responseError)
        } else if let writeError {
            continuation.resume(throwing: writeError)
        } else {
            continuation.resume(returning: destination)
        }
    }
}

enum FileChecksum {
    static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 兼容 `shasum -a 256` 的「hash  filename」和只写 hash 两种格式。
    static func digest(in text: String) -> String? {
        let pattern = "[0-9a-fA-F]{64}"
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(text[range]).lowercased()
    }
}
