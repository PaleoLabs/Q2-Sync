//
//  CardVerifier.swift
//  Q2-Sync › Core › SyncEngine
//
//  PURPOSE
//  "Verify Card": reads every song Q2 Sync put on the card and compares it,
//  byte for byte, with the song on the Mac, to catch files a microSD card
//  damaged silently. Damaged or missing songs can then be copied again
//  (`repairPlan`, applied by the normal `SyncExecutor`).
//
//  WHAT'S CHECKED
//  Songs in the manifest whose Mac file is available and unchanged since it
//  was copied. A song changed on the Mac is skipped (the next sync updates
//  it anyway), as is one whose Mac file isn't there (e.g. a disconnected
//  music drive).
//
//  SAFETY
//  Read-only: the Mac file is opened read-only, the card file is only read.
//  Nothing changes until the user chooses to re-copy.
//

import Foundation

/// One song that failed the check.
struct VerifyProblem: Sendable, Hashable, Identifiable {
    enum Kind: String, Sendable {
        /// The bytes on the card differ from the Mac file.
        case damaged
        /// The card file has the wrong size.
        case wrongSize
        /// The card file is gone.
        case missing
        /// The card file couldn't be read.
        case unreadable
    }
    let trackID: PersistentID
    let path: CardPath
    let title: String
    let kind: Kind
    var id: PersistentID { trackID }

    /// For the results list.
    var explanation: String {
        switch kind {
        case .damaged: return "Damaged: the card's copy differs from your Mac's"
        case .wrongSize: return "Damaged: the card's copy is the wrong size"
        case .missing: return "Missing from the card"
        case .unreadable: return "The card's copy couldn't be read"
        }
    }
}

/// What a check found.
struct VerifyResult: Sendable, Equatable {
    /// Songs checked and found identical.
    var verified = 0
    /// Songs that failed.
    var problems: [VerifyProblem] = []
    /// Skipped: changed on the Mac since copying (the next sync updates them).
    var skippedChanged = 0
    /// Skipped: the Mac file isn't available (cloud-only, missing, drive off).
    var skippedNoMacFile = 0
    /// Bytes read from the card.
    var bytesRead: UInt64 = 0
    /// `true` if the user stopped it early.
    var wasCancelled = false
}

/// Progress for the UI.
struct VerifyProgress: Sendable, Equatable {
    var bytesDone: UInt64 = 0
    var totalBytes: UInt64 = 0
    var songsDone = 0
    var totalSongs = 0
    var current = ""
    var fraction: Double { totalBytes == 0 ? 0 : min(1, Double(bytesDone) / Double(totalBytes)) }
}

/// Checks the card's songs against the Mac.
enum CardVerifier {

    /// Compares every checkable managed song.
    ///
    /// - Parameters:
    ///   - manifest: The card's manifest.
    ///   - tracks: The Mac library's tracks, by ID.
    ///   - fileSystem: The card (read only).
    ///   - onProgress: Called after each chunk (from the calling thread).
    /// - Returns: What was found. Cancelling returns what was found so far.
    static func verify(manifest: SyncManifest, tracks: [PersistentID: Track], fileSystem: CardFileSystem,
                       onProgress: (VerifyProgress) -> Void = { _ in }) -> VerifyResult {
        var result = VerifyResult()
        var checkable: [(id: PersistentID, entry: SyncManifest.Entry, track: Track, source: URL)] = []
        for (id, entry) in manifest.entries.sorted(by: { SortKey.compare($0.value.path, $1.value.path) }) {
            guard let track = tracks[id], track.isCopyable, let source = track.fileURL else {
                result.skippedNoMacFile += 1
                continue
            }
            if changedOnMac(track: track, entry: entry) {
                result.skippedChanged += 1
                continue
            }
            checkable.append((id, entry, track, source))
        }

        var progress = VerifyProgress(totalBytes: checkable.reduce(0) { $0 + $1.track.fileSize },
                                      totalSongs: checkable.count)
        onProgress(progress)
        var expectedDone: UInt64 = 0
        for item in checkable {
            if Task.isCancelled { result.wasCancelled = true; break }
            progress.current = item.track.title
            onProgress(progress)
            let kind = compare(card: fileSystem.urlForReading(item.entry.path), mac: item.source,
                               expectedSize: item.track.fileSize) { bytes in
                progress.bytesDone += UInt64(bytes)
                result.bytesRead += UInt64(bytes)
                onProgress(progress)
            }
            if Task.isCancelled && kind == nil { result.wasCancelled = true; break }
            switch kind {
            case nil: result.verified += 1
            case .some(let kind):
                result.problems.append(VerifyProblem(trackID: item.id, path: item.entry.path,
                                                     title: item.track.title, kind: kind))
            }
            progress.songsDone += 1
            // Keep the byte total honest when a file was cut short.
            expectedDone += item.track.fileSize
            progress.bytesDone = max(progress.bytesDone, expectedDone)
            onProgress(progress)
        }
        return result
    }

    /// Compares one card file with its Mac file.
    ///
    /// - Returns: `nil` if identical, otherwise what's wrong. A cancelled
    ///   comparison returns `nil` (the caller checks `Task.isCancelled`).
    static func compare(card: URL, mac: URL, expectedSize: UInt64, onBytes: (Int) -> Void = { _ in }) -> VerifyProblem.Kind? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: card.path) else { return .missing }
        let cardSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let macSize = ((try? FileManager.default.attributesOfItem(atPath: mac.path))?[.size] as? NSNumber)?.uint64Value
            ?? expectedSize
        guard cardSize == macSize else { return .wrongSize }
        guard let cardHandle = try? FileHandle(forReadingFrom: card) else { return .unreadable }
        defer { try? cardHandle.close() }
        // Read from the card itself, not from macOS's file cache: songs
        // copied earlier in this session may still be cached, and a check
        // against the cache would miss damage on the card.
        _ = fcntl(cardHandle.fileDescriptor, F_NOCACHE, 1)
        guard let macHandle = try? FileHandle(forReadingFrom: mac) else { return nil } // Mac side unreadable: can't judge
        defer { try? macHandle.close() }
        // One step per chunk pair: keep going, or stop with an answer.
        enum Step { case next(Int), done(VerifyProblem.Kind?) }
        while true {
            if Task.isCancelled { return nil }
            // FileHandle's reads hand back autoreleased buffers. Without a
            // pool per chunk they pile up until the whole check ends: a
            // full card's worth of memory, until macOS kills the app.
            let step: Step = autoreleasepool {
                let cardChunk: Data
                do { cardChunk = try cardHandle.read(upToCount: 1 << 20) ?? Data() } catch { return .done(.unreadable) }
                let macChunk = (try? macHandle.read(upToCount: 1 << 20)) ?? Data()
                if cardChunk.isEmpty && macChunk.isEmpty { return .done(nil) }
                if cardChunk != macChunk { return .done(.damaged) }
                return .next(cardChunk.count)
            }
            switch step {
            case .next(let count): onBytes(count)
            case .done(let answer): return answer
            }
        }
    }

    /// `true` if the Mac file changed after it was copied.
    static func changedOnMac(track: Track, entry: SyncManifest.Entry) -> Bool {
        if track.fileSize != entry.sourceSize { return true }
        guard let now = track.modifiedDate, let then = entry.sourceModified else { return false }
        return abs(now.timeIntervalSince(then)) > 1
    }

    /// A plan that copies the failed songs again, over their card copies.
    ///
    /// - Parameters:
    ///   - problems: From `verify`.
    ///   - tracks: The library's tracks, by ID.
    /// - Returns: A plan with only those copies.
    static func repairPlan(for problems: [VerifyProblem], tracks: [PersistentID: Track]) -> SyncPlan {
        var plan = SyncPlan()
        for problem in problems {
            guard let track = tracks[problem.trackID], track.isCopyable else { continue }
            plan.copies.append(CopyOperation(kind: .update, track: track, destination: problem.path,
                                             obsoletePath: nil,
                                             reason: problem.kind == .missing ? "Missing from the card" : "Damaged on the card"))
            plan.tracksByID[track.id] = track
        }
        return plan
    }
}
