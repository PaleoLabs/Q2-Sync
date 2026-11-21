//
//  FileDownloader.swift
//  Q2-Sync › App
//
//  PURPOSE
//  Downloads one file to a given place on the Mac, reporting progress, and
//  stopping if the Swift task is cancelled. Used for firmware files.
//
//  WHY NOT `URLSession.download(for:)`
//  The async one-liner doesn't report progress. A session delegate does:
//  URLSession calls `didWriteData` as bytes arrive, `didFinishDownloadingTo`
//  with a temporary file (which must be moved before that call returns),
//  and `didCompleteWithError` at the end.
//

import Foundation

/// Problems downloading.
enum DownloadError: LocalizedError, Equatable {
    case httpStatus(Int)
    case gotWebPage
    case noFile

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code): return "The server answered with an error (\(code))."
        case .gotWebPage: return "The server sent a web page instead of the file."
        case .noFile: return "The download didn't produce a file."
        }
    }
}

/// One download, with progress. Marked `@unchecked Sendable` because
/// URLSession calls it on its own queue; its state is guarded by `lock`.
final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    private let destination: URL
    private let onProgress: @Sendable (_ written: Int64, _ expected: Int64?) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var moveError: Error?
    private var response: HTTPURLResponse?

    private init(destination: URL, onProgress: @escaping @Sendable (Int64, Int64?) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    /// Downloads a URL to a file.
    ///
    /// - Parameters:
    ///   - url: What to download. Redirects are followed.
    ///   - destination: Where to put it (replaced if it exists).
    ///   - onProgress: Called (on a background queue) as bytes arrive.
    /// - Throws: `DownloadError`, network errors or `CancellationError`.
    /// - Side effects: Network access; writes `destination`. No cookies or
    ///   cache are kept (ephemeral session); the User-Agent is "Q2-Sync".
    static func download(_ url: URL, to destination: URL,
                         onProgress: @escaping @Sendable (Int64, Int64?) -> Void) async throws {
        let delegate = FileDownloader(destination: destination, onProgress: onProgress)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["User-Agent": "Q2-Sync"]
        configuration.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.lock.withLock { delegate.continuation = continuation }
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
        try Task.checkCancellation()
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let http = downloadTask.response as? HTTPURLResponse
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            lock.withLock { moveError = error }
        }
        lock.withLock { response = http }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, moveError, response) = lock.withLock {
            let state = (self.continuation, self.moveError, self.response)
            self.continuation = nil
            return state
        }
        guard let continuation else { return }
        if let error {
            continuation.resume(throwing: (error as? URLError)?.code == .cancelled ? CancellationError() : error)
        } else if let moveError {
            continuation.resume(throwing: moveError)
        } else if let response, !(200...299).contains(response.statusCode) {
            continuation.resume(throwing: DownloadError.httpStatus(response.statusCode))
        } else if response?.mimeType == "text/html" {
            continuation.resume(throwing: DownloadError.gotWebPage)
        } else if !FileManager.default.fileExists(atPath: destination.path) {
            continuation.resume(throwing: DownloadError.noFile)
        } else {
            continuation.resume()
        }
    }
}
