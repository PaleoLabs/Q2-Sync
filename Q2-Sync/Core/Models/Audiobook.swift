//
//  Audiobook.swift
//  Q2-Sync › Core › Models
//
//  PURPOSE
//  An `Audiobook` is our own, read-only description of one audiobook in
//  Apple Books: its title and author, and the audio files ("parts") that
//  make it up, in playing order.
//
//  HOW IT FITS
//  `AppleBooksSource` reads Apple Books' `Books.plist` and turns each
//  audiobook entry into an `Audiobook`. The Audiobooks tab, the sync
//  planner and the capacity bar work only with these values. Like `Track`,
//  it's a plain `Sendable` value: nothing here can change Apple Books.
//
//  Availability reuses `TrackAvailability`, so protected and not-downloaded
//  books are shown and explained the same way as songs.
//

import Foundation

/// One audio file of an audiobook. Most books have one; some have several.
struct AudiobookPart: Codable, Hashable, Sendable {

    /// Where the file lives on this Mac (inside Apple Books' folder).
    /// We only ever *read* from it.
    let fileURL: URL

    /// Track number from Apple Books. `0` means "unknown" (common for
    /// single-file books).
    let trackNumber: Int

    /// Disc number from Apple Books. `0` means "unknown".
    let discNumber: Int

    /// Length in seconds, `0` if Apple Books didn't record one.
    let durationSeconds: Double

    /// File size in bytes (the file's own size when it's on disk, otherwise
    /// what Apple Books recorded).
    let fileSize: UInt64

    /// The file's name, e.g. `Track 1.m4b`. Kept as-is on the card.
    var fileName: String { fileURL.lastPathComponent }
}

/// One audiobook from Apple Books, copied into a plain value.
struct Audiobook: Codable, Hashable, Identifiable, Sendable {

    /// Apple Books' identifier: `BKGeneratedItemId` (`sha1-…`) for books
    /// you added, the store's item ID for purchases. Stable across reads,
    /// so it's what a Q2's saved selection remembers.
    let id: String

    /// The book's title. Never empty: falls back to its folder name.
    let title: String

    /// Author, if Apple Books has one.
    let author: String?

    /// The whole book's length in seconds.
    let durationSeconds: Double

    /// The audio files, in playing order (disc, then track, then file name).
    let parts: [AudiobookPart]

    /// Whether the book can be copied, and if not, why not.
    let availability: TrackAvailability

    /// Total size of all parts in bytes.
    var totalSize: UInt64 { parts.reduce(0) { $0 + $1.fileSize } }

    /// `true` if a part is long enough that Q2 Pod may refuse to play it.
    var hasLongPart: Bool {
        parts.contains { $0.durationSeconds > Self.longPartWarningSeconds }
    }

    /// Q2 Pod refuses a single file too big for the Q2's memory, which its
    /// README puts at "around 40 hours". It's a memory limit, not a time
    /// limit, so this is only a warning: a 16-hour book has played fine.
    static let longPartWarningSeconds: Double = 35 * 3600
}
