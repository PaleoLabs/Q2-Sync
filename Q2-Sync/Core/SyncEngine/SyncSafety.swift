//
//  SyncSafety.swift
//  Q2-Sync › Core › SyncEngine
//
//  PURPOSE
//  The last checks before a plan may be applied. Collects everything that
//  must STOP the sync ("blockers") and everything that needs the user's
//  explicit extra confirmation.
//
//  RULES
//  Blockers (the sync can't be applied):
//   • The library failed the "Mac looks empty" check.
//   • This is the device's first sync: it may be applied by hand, but
//     never automatically (see `AutoSyncPolicy`).
//   • The new songs won't fit on the card.
//  Extra confirmation required:
//   • Removing more than 20% of the songs on the card (planned removals
//     plus card-only files set to trash or delete).
//
//  HOW IT FITS
//  The preview sheet shows the assessment; the executor re-checks the
//  removal confirmation itself (defence in depth). Auto-sync
//  stops and waits for the user whenever anything here needs attention.
//

import Foundation

/// The result of the pre-sync safety checks.
struct SafetyAssessment: Sendable, Equatable {
    /// Reasons the sync can't be applied. Empty means it may proceed.
    var blockers: [String] = []
    /// `true` if nothing has been synced to this card yet. Doesn't block a
    /// sync you start yourself; automatic syncs wait for you instead.
    var isFirstSync = false
    /// `true` if removals exceed the threshold and need extra confirmation.
    var needsLargeRemovalConfirmation = false
    /// Free space left after the sync, in bytes (negative = won't fit).
    var projectedFreeBytes: Int64 = 0

    /// `true` if nothing blocks applying the plan.
    var canApply: Bool { blockers.isEmpty }
}

/// Pre-sync safety checks.
enum SyncSafety {

    /// Removing more than this fraction of managed songs needs extra confirmation.
    static let largeRemovalThreshold = 0.20

    /// Space always left free on the card (firmware caches need room;
    /// Q2 Pod's Cover Flow needs 16 MB), in bytes.
    static let reservedFreeBytes: Int64 = 200 * 1_000_000

    /// Checks a plan before it may be applied.
    ///
    /// - Parameters:
    ///   - plan: The planned sync.
    ///   - health: The library health check result.
    ///   - isFirstSync: `true` if nothing has been synced to this device yet.
    ///   - availableBytes: Free space on the card now.
    ///   - includeRemovals: Whether removals will be applied.
    ///   - cardOnlyActions: The user's choices for card-only files; those
    ///     set to move to the Mac or delete count as removals too, and free
    ///     their space.
    /// - Returns: The assessment.
    static func assess(plan: SyncPlan, health: LibraryHealth, isFirstSync: Bool,
                       availableBytes: Int64, includeRemovals: Bool,
                       cardOnlyActions: [CardPath: CardOnlyAction] = [:]) -> SafetyAssessment {
        var result = SafetyAssessment()

        if case .unsafe(let reason) = health {
            result.blockers.append(reason)
        }

        result.isFirstSync = isFirstSync

        let cardOnlyFreed = plan.cardOnly
            .filter { cardOnlyActions[$0.path]?.removesFromCard == true }
            .reduce(Int64(0)) { $0 + Int64($1.size) }
        let removalsFreed = includeRemovals
            ? Int64(plan.bytesFreedByRemovals + plan.audiobooks.bytesFreedByRemovals) : 0
        let replacedAudiobookFiles = Int64(plan.audiobooks.replacedFiles.reduce(0) { $0 + $1.cardSize })
        let freed = Int64(plan.bytesFreedByUpdates) + cardOnlyFreed + removalsFreed + replacedAudiobookFiles
        result.projectedFreeBytes = availableBytes + freed - Int64(plan.allBytesToCopy)
        if result.projectedFreeBytes < reservedFreeBytes {
            let short = reservedFreeBytes - result.projectedFreeBytes
            let message = "The selected music doesn't fit on the card. Deselect about "
                + "\(short.formatted(ByteCountFormatStyle(style: .file))) of music and try again."
            result.blockers.append(message)
        }

        result.needsLargeRemovalConfirmation =
            plan.removalFraction(cardOnlyActions: cardOnlyActions, includeRemovals: includeRemovals) > largeRemovalThreshold
        return result
    }
}
