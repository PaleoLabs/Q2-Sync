//
//  TimeRemaining.swift
//  Q2-Sync › Core › SyncEngine
//
//  PURPOSE
//  Estimates how long the rest of a sync's copying will take, for the
//  progress window ("About 12 minutes remaining"). It counts "units":
//  bytes for copying songs, or files for the removal step and covers for
//  the album-cover step (each gets its own estimator with smaller minimums).
//
//  HOW
//  Copying speed is measured from when the first bytes arrive (so time
//  spent on removals or renames beforehand doesn't count), and smoothed so
//  the estimate doesn't jump around with each song: the average speed so
//  far, nudged towards the speed of the last ~20 seconds. Nothing is shown
//  until there's enough to go on (10 seconds and 5 MB of copying).
//

import Foundation

/// A running estimate of the copying time left.
struct TimeRemainingEstimator: Sendable {

    /// Measured for at least this long before estimating.
    let minimumSeconds: TimeInterval
    /// …and at least this many units (bytes, or covers).
    let minimumUnits: UInt64
    /// Length of the "recent speed" window.
    static let windowSeconds: TimeInterval = 20

    /// When and at what byte count copying started.
    private var start: (time: TimeInterval, bytes: UInt64)?
    /// Recent samples, for the recent speed.
    private var samples: [(time: TimeInterval, bytes: UInt64)] = []

    /// - Parameters:
    ///   - minimumSeconds: Time measured before the first estimate.
    ///   - minimumUnits: Units done before the first estimate. The defaults
    ///     suit copying bytes (10 seconds and 5 MB).
    init(minimumSeconds: TimeInterval = 10, minimumUnits: UInt64 = 5_000_000) {
        self.minimumSeconds = minimumSeconds
        self.minimumUnits = minimumUnits
    }

    /// For the album-cover step: covers, not bytes.
    static func forCovers() -> TimeRemainingEstimator {
        TimeRemainingEstimator(minimumSeconds: 5, minimumUnits: 3)
    }

    /// For the removal step: files removed, not bytes (#62).
    static func forRemovals() -> TimeRemainingEstimator {
        TimeRemainingEstimator(minimumSeconds: 5, minimumUnits: 10)
    }

    /// Adds a progress sample and returns the seconds left, if known.
    ///
    /// - Parameters:
    ///   - bytesCopied: Bytes copied so far.
    ///   - totalBytes: Bytes to copy in all.
    ///   - time: Now, in seconds (any steady clock).
    /// - Returns: Seconds remaining, or `nil` until there's enough data.
    mutating func update(bytesCopied: UInt64, totalBytes: UInt64, at time: TimeInterval) -> TimeInterval? {
        guard totalBytes > 0 else { return nil }
        guard bytesCopied > 0 else { return nil }
        if start == nil { start = (time, bytesCopied); samples = [(time, bytesCopied)]; return nil }
        // Progress hops to the main thread in separate tasks, which can
        // arrive out of order: ignore a sample that goes backwards (the
        // unsigned subtractions below would otherwise crash).
        if let last = samples.last, bytesCopied < last.bytes || time < last.time { return nil }
        samples.append((time, bytesCopied))
        samples.removeAll { time - $0.time > Self.windowSeconds }

        guard let start, time - start.time >= minimumSeconds,
              bytesCopied - start.bytes >= minimumUnits else { return nil }
        let overall = Double(bytesCopied - start.bytes) / (time - start.time)
        var speed = overall
        if let first = samples.first, time - first.time >= 5, bytesCopied > first.bytes {
            let recent = Double(bytesCopied - first.bytes) / (time - first.time)
            speed = 0.6 * overall + 0.4 * recent
        }
        guard speed > 0 else { return nil }
        return Double(totalBytes.saturatingSubtract(bytesCopied)) / speed
    }

    /// Friendly text, e.g. "About 12 minutes remaining".
    ///
    /// - Parameter seconds: Seconds left.
    static func describe(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "Less than a minute remaining" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return minutes == 1 ? "About 1 minute remaining" : "About \(minutes) minutes remaining" }
        let hours = minutes / 60, rest = minutes % 60
        let hourText = hours == 1 ? "1 hour" : "\(hours) hours"
        // Past an hour, five-minute steps are precise enough.
        let roundedRest = Int((Double(rest) / 5).rounded()) * 5
        if roundedRest == 0 || roundedRest == 60 {
            let whole = roundedRest == 60 ? hours + 1 : hours
            return "About \(whole == 1 ? "1 hour" : "\(whole) hours") remaining"
        }
        return "About \(hourText) \(roundedRest) minutes remaining"
    }
}

private extension UInt64 {
    func saturatingSubtract(_ other: UInt64) -> UInt64 { self > other ? self - other : 0 }
}
