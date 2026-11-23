//
//  TimeLimit.swift
//  Q2-Sync › Core › Library
//
//  PURPOSE
//  Waits for a task's result for at most a set time. Used for reading the
//  Music library: if macOS's library service (AMPLibraryAgent) stops
//  answering, `ITLibrary` never returns, and Q2 Sync would show "Reading
//  Music library…" forever.
//
//  WHY NOT A TASK GROUP
//  A task group waits for all its children before it returns, and a child
//  awaiting the stuck read can't be cancelled (ITLibrary ignores Swift
//  cancellation). So the wait races two plain tasks instead, and the first
//  to finish resumes the caller. The read itself keeps running; the caller
//  decides what to do with it (see `LibraryModel`).
//

import Foundation

/// Waiting with a time limit.
enum TimeLimit {

    /// The task's result, or `nil` if `limit` passed first.
    ///
    /// - Parameters:
    ///   - task: The work to wait for. It isn't cancelled on timeout.
    ///   - limit: How long to wait.
    /// - Returns: The task's result, or `nil` on timeout.
    static func result<Value: Sendable>(of task: Task<Value, any Error>,
                                        within limit: Duration) async -> Result<Value, any Error>? {
        let gate = ResumeOnce()
        return await withCheckedContinuation { continuation in
            Task {
                let result = await task.result
                if gate.claim() { continuation.resume(returning: result) }
            }
            Task {
                try? await Task.sleep(for: limit)
                if gate.claim() { continuation.resume(returning: nil) }
            }
        }
    }
}

/// Lets exactly one of two racers resume a continuation.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// `true` the first time only.
    func claim() -> Bool {
        lock.withLock {
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}
