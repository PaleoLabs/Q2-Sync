//
//  SyncManifest.swift
//  Q2-Sync › Core › SyncEngine
//
//  PURPOSE
//  The manifest is Q2 Sync's record of what it has put on the card: for
//  each song, where it is and what the Mac file looked like when copied.
//  It's what makes repeat syncs fast (unchanged songs are skipped) and
//  lets the app tell its own files apart from files someone else put on
//  the card.
//
//  WHERE IT LIVES
//  On the card, at `.q2sync/manifest.json`. Keeping it on the card means
//  it always describes THAT card, even if you use it with another Mac.
//
//  HOW IT FITS
//  Loaded before planning, updated by the executor as files are copied,
//  and saved (atomically) every few files and at the end, so a cancelled
//  or interrupted sync still leaves an accurate record.
//

import Foundation

/// Q2 Sync's record of the songs it manages on one card.
struct SyncManifest: Codable, Sendable, Equatable {

    /// One managed song on the card.
    struct Entry: Codable, Sendable, Hashable {
        /// Where the song is on the card.
        var path: CardPath
        /// Mac file size when copied (from the library record).
        var sourceSize: UInt64
        /// Mac file modification date when copied (from the library).
        var sourceModified: Date?
        /// Size of the file on the card after copying.
        var cardSize: UInt64
        /// When it was copied.
        var syncedAt: Date
        /// Tags, kept so reports can name songs even after they leave the
        /// Mac library.
        var title: String
        var artist: String?
        var album: String?
    }

    /// Bumped if the file format ever changes incompatibly.
    var formatVersion = 1

    /// Managed songs, by Apple Music persistent ID.
    var entries: [PersistentID: Entry] = [:]

    /// Playlist files Q2 Sync wrote (card paths), so it only ever replaces
    /// or removes its own playlists.
    var playlistFiles: [PersistentID: CardPath] = [:]

    /// SHA-256 of each playlist file as it was last put up for import, by
    /// playlist ID. Lets a sync put only changed playlists in the import
    /// folder. Optional so older manifests still load.
    var playlistDigests: [PersistentID: String]?

    /// Album covers Q2 Sync wrote, by card path (`…/cover.jpg`). Optional
    /// so manifests from before covers existed still load.
    var albumCovers: [CardPath: CoverEntry]?

    /// One cover Q2 Sync wrote.
    struct CoverEntry: Codable, Sendable, Hashable {
        /// Which artwork it was made from (see `AlbumCovers.sourceKey`).
        var sourceKey: String
        /// When it was written.
        var writtenAt: Date
    }

    /// Audiobooks Q2 Sync put in `Audiobooks/`, by Apple Books id.
    /// Optional so manifests from before audiobooks still load.
    var audiobooks: [String: AudiobookRecord]?

    /// Podcast episodes Q2 Sync put in `Podcasts/`, by the Podcasts app's
    /// episode UUID. Optional so older manifests still load.
    var podcasts: [String: PodcastEpisodeRecord]?

    /// When the manifest was last saved.
    var updatedAt: Date?

    /// Card path of the manifest for a profile.
    static func path(for profile: DeviceProfile) -> CardPath {
        "\(profile.appStateFolderName)/manifest.json"
    }

    /// Reads the manifest from the card.
    ///
    /// - Parameter fileSystem: The card.
    /// - Returns: The manifest, or an empty one if there isn't one yet.
    /// - Throws: `ManifestError.unreadable` if a manifest exists but is
    ///   damaged. We stop rather than guess, because a wrong manifest could
    ///   make the planner misjudge what's on the card.
    static func load(from fileSystem: CardFileSystem) throws -> SyncManifest {
        try load(cardRoot: fileSystem.pathGuard.cardRoot, profile: fileSystem.pathGuard.profile)
    }

    /// Reads the manifest given just the card root (reading needs no guard).
    ///
    /// - Parameters:
    ///   - cardRoot: The card's root folder.
    ///   - profile: For the manifest's location.
    /// - Returns: The manifest, or an empty one if there isn't one yet.
    /// - Throws: `ManifestError.unreadable` if it exists but is damaged.
    static func load(cardRoot: URL, profile: DeviceProfile) throws -> SyncManifest {
        let url = cardRoot.appending(path: path(for: profile))
        guard FileManager.default.fileExists(atPath: url.path) else { return SyncManifest() }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SyncManifest.self, from: Data(contentsOf: url))
        } catch {
            throw ManifestError.unreadable(error.localizedDescription)
        }
    }

    /// Saves the manifest to the card (temp file + rename).
    ///
    /// - Parameter fileSystem: The card.
    /// - Throws: Guard or file-system errors.
    mutating func save(to fileSystem: CardFileSystem) throws {
        updatedAt = .now
        let encoder = JSONEncoder()
        // Compact (no indentation): it's read only by Q2 Sync, and is
        // rewritten during big syncs, so size matters.
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try fileSystem.writeAtomically(try encoder.encode(self), to: Self.path(for: fileSystem.pathGuard.profile))
    }
}

/// Manifest problems.
enum ManifestError: LocalizedError, Equatable {
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let reason):
            return "Q2 Sync's record of this card (.q2sync/manifest.json) is damaged, so syncing has stopped to be safe. (\(reason))"
        }
    }
}
