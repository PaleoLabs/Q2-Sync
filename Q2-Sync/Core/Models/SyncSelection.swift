//
//  SyncSelection.swift
//  Q2-Sync › Core › Models
//
//  PURPOSE
//  What the user ticked for a device: either "entire library", or a set of
//  artists, albums, genres and playlists, like Finder's iPod sync.
//
//  HOW IT FITS
//  Saved per device (inside `KnownDevice`). `SelectionResolver` turns it
//  into the exact list of tracks to sync from a `LibrarySnapshot`.
//
//  WHY KEYS INSTEAD OF TRACK IDS
//  We store what the user *meant* ("all of Radiohead"), not a frozen track
//  list. So when you add a new Radiohead album to Music, the next sync
//  picks it up automatically, just like Finder did for iPods.
//

import Foundation

/// The user's choice of what to sync to one device.
struct SyncSelection: Codable, Hashable, Sendable {

    /// "Sync music onto [Q2]". On by default: a new Q2 syncs music, as
    /// before this setting existed. Off means no music on the card: the
    /// songs and playlists Q2 Sync put there are removed (with Remove
    /// Them), and the Apple Music library isn't read at all.
    var isEnabled = true

    /// The two modes offered in the UI.
    enum Mode: String, Codable, Sendable {
        /// Every song in the library (and every playlist).
        case entireLibrary
        /// Only the ticked artists, albums, genres and playlists.
        case selectedItems
    }

    /// Which mode is active.
    var mode: Mode = .selectedItems

    /// Ticked artists, as `TrackGroup.id` values (e.g. `"artist:adele"`).
    var artistIDs: Set<String> = []

    /// Ticked albums, as `TrackGroup.id` values (e.g. `"album:adele|25"`).
    var albumIDs: Set<String> = []

    /// Ticked genres, as `TrackGroup.id` values (e.g. `"genre:rock"`).
    var genreIDs: Set<String> = []

    /// Ticked playlists, by playlist persistent ID.
    var playlistIDs: Set<PersistentID> = []

    /// `true` if nothing at all is ticked (and not entire-library mode).
    /// Says nothing about `isEnabled`; see `choosesNothing`.
    var isEmpty: Bool {
        mode == .selectedItems && artistIDs.isEmpty && albumIDs.isEmpty
            && genreIDs.isEmpty && playlistIDs.isEmpty
    }

    /// Total number of ticked items across all sections.
    var tickedItemCount: Int {
        artistIDs.count + albumIDs.count + genreIDs.count + playlistIDs.count
    }
}

// MARK: - Loading saved selections

extension SyncSelection {

    private enum CodingKeys: String, CodingKey {
        case isEnabled, mode, artistIDs, albumIDs, genreIDs, playlistIDs
    }

    /// Missing keys decode to their defaults, so selections saved before
    /// a property existed (such as `isEnabled`) load with their ticks
    /// intact instead of failing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .selectedItems
        artistIDs = try c.decodeIfPresent(Set<String>.self, forKey: .artistIDs) ?? []
        albumIDs = try c.decodeIfPresent(Set<String>.self, forKey: .albumIDs) ?? []
        genreIDs = try c.decodeIfPresent(Set<String>.self, forKey: .genreIDs) ?? []
        playlistIDs = try c.decodeIfPresent(Set<PersistentID>.self, forKey: .playlistIDs) ?? []
    }
}

extension SyncSelection: ContentSyncChoice {

    /// `true` if music is off, or on with nothing ticked.
    var choosesNothing: Bool { !isEnabled || isEmpty }
}
