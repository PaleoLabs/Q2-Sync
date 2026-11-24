//
//  Track.swift
//  Q2-Sync › Core › Models
//
//  PURPOSE
//  A `Track` is our own, simple, read-only description of one song in the
//  Apple Music library.
//
//  HOW IT FITS
//  The Library layer (see `ITunesLibrarySource`) reads Apple's
//  `ITLibMediaItem` objects and immediately converts each one into a
//  `Track`. Everything else in the app (selection, sync planning, playlist
//  writing) works only with `Track` values and never with Apple's objects.
//
//  Why copy the data instead of using Apple's objects directly?
//  • Safety: our code can never accidentally call anything on the library.
//  • Concurrency: `Track` is a plain value (a `struct`) that is `Sendable`,
//    meaning Swift can prove it's safe to pass between threads.
//  • Testing: tests can create `Track`s by hand without a real library.
//

import Foundation

/// The library's stable identifier for a track or playlist.
///
/// Apple Music gives every item a 64-bit "persistent ID". We store it as a
/// 16-digit uppercase hexadecimal string (the same style Apple uses in its
/// XML exports), e.g. `"1A2B3C4D5E6F7081"`.
typealias PersistentID = String

/// Whether a track's audio file can actually be copied to the card.
///
/// Only `.available` tracks are ever copied. Everything else is reported in
/// the sync report as "skipped", with this value explaining why.
enum TrackAvailability: String, Codable, Sendable, CaseIterable {
    /// A local, unprotected file that exists on disk. Safe to copy.
    case available

    /// The song lives only in iCloud / Apple Music streaming. We never
    /// trigger a download, so it's skipped.
    case cloudOnly

    /// Protected by DRM (old iTunes Store purchases or Apple Music
    /// downloads). The Q2 can't play these, so they're skipped.
    case drmProtected

    /// The library says there's a file, but it isn't on disk right now
    /// (for example, an external music drive is disconnected).
    case fileMissing

    /// Not a song at all for our purposes (a stream URL, a video, etc.).
    case unsupported

    /// A short, user-facing explanation for the sync report.
    var reportDescription: String {
        switch self {
        case .available:    return "Available"
        case .cloudOnly:    return "In the cloud only (not downloaded)"
        case .drmProtected: return "Protected (DRM)"
        case .fileMissing:  return "File not found on disk"
        case .unsupported:  return "Not a supported audio file"
        }
    }
}

/// One song from the Apple Music library, copied into a plain value.
///
/// All properties are `let` constants: once read, a `Track` never changes.
/// `Codable` lets us save tracks to JSON (used by test fixtures), and
/// `Hashable`/`Identifiable` let SwiftUI lists and `Set`s work with them.
struct Track: Codable, Hashable, Identifiable, Sendable {

    // MARK: Identity

    /// Apple Music's persistent ID for this track (hex string).
    let id: PersistentID

    // MARK: Tags (the Q2 builds its library from these)

    /// Song title. Never empty: falls back to the file name.
    let title: String

    /// Track artist, e.g. "Paul McCartney & Wings". `nil` if untagged.
    let artist: String?

    /// Album artist, e.g. "Wings". Q2 Pod groups albums by this, so it
    /// matters a lot. `nil` if untagged.
    let albumArtist: String?

    /// Album title. `nil` if untagged.
    let album: String?

    /// Genre name. `nil` if untagged.
    let genre: String?

    /// Track number on its disc (1-based). `0` means "unknown".
    let trackNumber: Int

    /// Disc number (1-based). `0` means "unknown".
    let discNumber: Int

    /// Number of discs in the album. `0` means "unknown".
    let discCount: Int

    /// `true` when the album is marked as a compilation in Music.
    let isCompilation: Bool

    // MARK: File facts

    /// Length in seconds (Apple reports milliseconds; we convert).
    let durationSeconds: Double

    /// File size in bytes, as recorded by the library.
    let fileSize: UInt64

    /// Where the audio file lives on this Mac, if it's a local file.
    /// We only ever *read* from this location.
    let fileURL: URL?

    /// Human-readable file kind from Music, e.g. "MPEG audio file".
    let fileKind: String?

    /// When the file was last modified, according to the library.
    /// Used later to detect changed tracks that need re-copying.
    let modifiedDate: Date?

    /// Whether this track can be copied, and if not, why not.
    let availability: TrackAvailability

    /// `true` if Apple Music has artwork for this track (embedded or in its
    /// own database). Used for album covers. Optional so older fixture
    /// files still decode.
    var hasArtwork: Bool? = nil

    // MARK: Details (shown in the song inspector only)
    // Optional so older fixture files still decode; `nil` means unknown.

    /// Release year, e.g. 1977.
    var year: Int? = nil

    /// Composer, if tagged.
    var composer: String? = nil

    /// Bit rate in kbps, e.g. 256.
    var bitRate: Int? = nil

    /// Sample rate in Hz, e.g. 44_100.
    var sampleRate: Int? = nil

    /// How many times it has been played in Music.
    var playCount: Int? = nil

    /// When it was added to the Music library.
    var dateAdded: Date? = nil

    /// When it was last played in Music.
    var lastPlayed: Date? = nil

    // MARK: Convenience

    /// The name we group this track's album under.
    ///
    /// Mirrors how Q2 Pod groups albums (album artist first). For
    /// compilations without an album artist we use "Various Artists" so
    /// the album isn't split into one album per track artist.
    var effectiveAlbumArtist: String {
        if let albumArtist, !albumArtist.isEmpty { return albumArtist }
        if isCompilation { return "Various Artists" }
        return artist ?? "Unknown Artist"
    }

    /// The artist name shown in the "Artists" section of the selection UI.
    var displayArtist: String { artist?.nonEmpty ?? "Unknown Artist" }

    /// The album name shown in the UI.
    var displayAlbum: String { album?.nonEmpty ?? "Unknown Album" }

    /// The genre name shown in the UI.
    var displayGenre: String { genre?.nonEmpty ?? "Unknown Genre" }

    /// `true` if this track can be copied to the card.
    var isCopyable: Bool { availability == .available }

    /// Why this track can't be copied, in words. For a missing file this
    /// says where it went (Trash, a drive that isn't connected, or moved);
    /// for the other kinds it is the plain `reportDescription`.
    ///
    /// Checked when asked, not when the library is read, so it follows the
    /// drive being plugged in or the file being restored.
    ///
    /// - Side effects: Only checks whether folders exist. Nothing is opened.
    var unavailableReason: String {
        guard availability == .fileMissing else { return availability.reportDescription }
        return Self.missingFileReason(for: fileURL)
    }

    /// Works out where a missing file went from its last known location.
    ///
    /// - Parameters:
    ///   - fileURL: Where Music last expected the file.
    ///   - fileManager: Injectable so tests can use temp folders.
    /// - Returns: A short reason, e.g. "In the Trash" or
    ///   "On \"Music Drive\", which isn't connected".
    static func missingFileReason(for fileURL: URL?, fileManager: FileManager = .default) -> String {
        guard let fileURL else { return "File not found on disk" }
        let parts = fileURL.standardizedFileURL.pathComponents

        // In a Trash folder (the user's, or a drive's .Trashes).
        if parts.contains(".Trash") || parts.contains(".Trashes") {
            return "In the Trash"
        }

        // On a drive under /Volumes that isn't mounted right now.
        if parts.count > 2, parts[1] == "Volumes" {
            let volume = URL(filePath: "/Volumes").appending(path: parts[2])
            if !fileManager.fileExists(atPath: volume.path) {
                return "On \u{201C}\(parts[2])\u{201D}, which isn't connected"
            }
        }

        // The drive (or Mac) is there, but the file isn't.
        let folder = fileURL.deletingLastPathComponent().path
        if fileManager.fileExists(atPath: folder) {
            return "Moved or renamed (its folder is still there)"
        }
        return "Moved or deleted (its folder is gone)"
    }
}

extension String {
    /// Returns `nil` for an empty or whitespace-only string, otherwise the
    /// string itself. Handy for tag fields that are present-but-blank.
    var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
