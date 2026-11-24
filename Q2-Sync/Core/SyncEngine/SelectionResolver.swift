//
//  SelectionResolver.swift
//  Q2-Sync › Core › SyncEngine
//
//  PURPOSE
//  Turns a `SyncSelection` ("these artists, albums, genres, playlists")
//  into the concrete set of tracks and playlists to sync, plus the list of
//  tracks that will be skipped and why.
//
//  HOW IT FITS
//      SyncSelection + LibrarySnapshot ──resolve──▶ ResolvedSelection
//            ──▶ shown as the selection summary in the UI
//            ──▶ input to the sync planner
//
//  RULE
//  The tracks to sync are the UNION of everything ticked: a song is
//  included if its artist OR its album OR its genre OR any playlist it's
//  in is ticked. Only `available` tracks are copied; cloud-only, DRM and
//  missing files are listed as skipped and never downloaded.
//

import Foundation

/// The concrete result of resolving a selection against a library.
struct ResolvedSelection: Sendable {

    /// Tracks that will be copied, without duplicates, in a stable order
    /// (album artist, album, disc, track).
    let tracksToSync: [Track]

    /// Selected tracks that can't be copied, with the reason in each
    /// track's `availability`.
    let skippedTracks: [Track]

    /// Playlists to write to the card (folders excluded).
    let playlists: [Playlist]

    /// Ticked items that no longer exist in the library (for example an
    /// album you deleted from Music). They're ignored, never an error.
    let missingSelectionCount: Int

    /// Total size of `tracksToSync`, in bytes, from the library's records.
    var totalBytes: UInt64 { tracksToSync.reduce(0) { $0 + $1.fileSize } }

    /// Total playing time of `tracksToSync`, in seconds.
    var totalDurationSeconds: Double { tracksToSync.reduce(0) { $0 + $1.durationSeconds } }

    /// Skipped tracks counted by reason, for the summary line.
    var skippedCounts: [TrackAvailability: Int] {
        Dictionary(grouping: skippedTracks, by: \.availability).mapValues(\.count)
    }
}

/// Resolves selections. A namespace (`enum` with no cases) for pure functions.
enum SelectionResolver {

    /// Resolves a selection against a library snapshot.
    ///
    /// - Parameters:
    ///   - selection: What the user ticked.
    ///   - snapshot: The current library.
    /// - Returns: Tracks to sync, tracks skipped, and playlists.
    /// - Side effects: None. Pure computation.
    static func resolve(_ selection: SyncSelection, in snapshot: LibrarySnapshot) -> ResolvedSelection {
        let userPlaylists = snapshot.playlists.filter { $0.kind != .folder }

        // Step 1: work out which track IDs are selected, and which playlists.
        var selectedIDs = Set<PersistentID>()
        var playlists: [Playlist] = []
        var missing = 0

        switch selection.mode {
        case .entireLibrary:
            selectedIDs = Set(snapshot.tracks.map(\.id))
            playlists = userPlaylists

        case .selectedItems:
            // Artists, albums and genres share the same lookup approach.
            let sections: [(ids: Set<String>, prefix: String)] = [
                (selection.artistIDs, "artist"),
                (selection.albumIDs, "album"),
                (selection.genreIDs, "genre"),
            ]
            for section in sections where !section.ids.isEmpty {
                let groupsByID = snapshot.groupsByID(section.prefix) // kept by the snapshot
                for id in section.ids {
                    if let group = groupsByID[id] {
                        selectedIDs.formUnion(group.trackIDs)
                    } else {
                        missing += 1
                    }
                }
            }

            let playlistsByID = Dictionary(userPlaylists.map { ($0.id, $0) },
                                           uniquingKeysWith: { first, _ in first })
            for id in selection.playlistIDs {
                if let playlist = playlistsByID[id] {
                    playlists.append(playlist)
                    selectedIDs.formUnion(playlist.trackIDs)
                } else {
                    missing += 1
                }
            }
            playlists.sort { SortKey.compare($0.name, $1.name) }
        }
        playlists = PlaylistNaming.disambiguate(playlists, folders: snapshot.playlists.filter { $0.kind == .folder })

        // Step 2: split into copyable and skipped, in a stable order. The
        // whole library is sorted once per snapshot and kept; filtering it
        // keeps that order (`libraryOrder` is a total order), so a click
        // on the Music tab doesn't re-sort ~10,000 songs.
        let selectedTracks = tracksInLibraryOrder(snapshot).filter { selectedIDs.contains($0.id) }

        return ResolvedSelection(
            tracksToSync: selectedTracks.filter(\.isCopyable),
            skippedTracks: selectedTracks.filter { !$0.isCopyable },
            playlists: playlists,
            missingSelectionCount: missing
        )
    }

    /// Every track in `libraryOrder`, sorted once per snapshot.
    static func tracksInLibraryOrder(_ snapshot: LibrarySnapshot) -> [Track] {
        snapshot.memoized("tracksInLibraryOrder") { snapshot.tracks.sorted(by: libraryOrder) }
    }

    /// Works out the groupings and orderings the Music tab and the
    /// resolver use, so the first click doesn't. Call off the main thread
    /// right after reading the library.
    static func prepare(_ snapshot: LibrarySnapshot) {
        for prefix in ["artist", "album", "genre"] { _ = snapshot.groupsByID(prefix) }
        _ = tracksInLibraryOrder(snapshot)
    }

    /// Orders tracks by album artist, album, disc, track, then title, so the
    /// copy runs album by album (nicer progress, and partial syncs leave
    /// whole albums on the card).
    private static func libraryOrder(_ a: Track, _ b: Track) -> Bool {
        if a.effectiveAlbumArtist != b.effectiveAlbumArtist {
            return SortKey.compare(a.effectiveAlbumArtist, b.effectiveAlbumArtist)
        }
        if a.displayAlbum != b.displayAlbum { return SortKey.compare(a.displayAlbum, b.displayAlbum) }
        if a.discNumber != b.discNumber { return a.discNumber < b.discNumber }
        if a.trackNumber != b.trackNumber { return a.trackNumber < b.trackNumber }
        if a.title != b.title { return a.title.localizedStandardCompare(b.title) == .orderedAscending }
        return a.id < b.id
    }
}

/// Gives playlists that share a name a clearer name for the card.
///
/// Music allows several playlists with the same name (say "1980's Music" in
/// a "Decades" folder and another at the top level). On the Q2 the name is
/// all you see, and the card would get "1980's Music (2)". Instead, each
/// same-named playlist inside a folder is named after it:
/// "Decades - 1980's Music". Playlists still sharing a name after that
/// (both at the top level) keep it, and `PlaylistWriter` numbers them.
enum PlaylistNaming {

    /// - Parameters:
    ///   - playlists: The selected playlists (no folders).
    ///   - folders: The library's playlist folders, for their names.
    /// - Returns: The playlists, with clashing names in folders prefixed.
    static func disambiguate(_ playlists: [Playlist], folders: [Playlist]) -> [Playlist] {
        let folderNames = Dictionary(folders.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var counts: [String: Int] = [:]
        for playlist in playlists { counts[playlist.name.lowercased(), default: 0] += 1 }
        return playlists.map { playlist in
            guard counts[playlist.name.lowercased(), default: 0] > 1,
                  let parent = playlist.parentID, let folder = folderNames[parent], !folder.isEmpty else {
                return playlist
            }
            return Playlist(id: playlist.id, name: "\(folder) - \(playlist.name)", kind: playlist.kind,
                            parentID: playlist.parentID, trackIDs: playlist.trackIDs)
        }
    }
}
