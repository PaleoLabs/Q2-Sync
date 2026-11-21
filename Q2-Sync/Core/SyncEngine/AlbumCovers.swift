//
//  AlbumCovers.swift
//  Q2-Sync › Core › SyncEngine
//
//  PURPOSE
//  Puts a `cover.jpg` in each album folder on the card, made from the
//  album's artwork in Apple Music, so the Q2 shows covers even for songs
//  whose files have no artwork embedded. (Apple Music often keeps artwork
//  in its own database rather than inside the song file.)
//
//  WHAT THE Q2 LOOKS FOR (Q2 Pod docs/internals.md, checked 2026-11-21)
//  The album grid uses `cover.jpg`, then `folder.jpg`, then embedded art;
//  Cover Flow tries embedded art, then `cover`/`folder` `.jpg`/`.png`.
//  Stock's decoder handles a BASELINE JPEG cheaply at any size, but a
//  large progressive JPEG or PNG can run the player out of memory. So
//  covers are written as baseline RGB JPEGs, at most 1000 px
//  (`CoverImage.makeJPEG`).
//
//  RULES
//  • Only folders holding songs Q2 Sync manages get a cover.
//  • A folder that already has your own cover.jpg / folder.jpg / .png is
//    left alone: Q2 Sync never replaces artwork it didn't write.
//  • Q2 Sync's covers are recorded in the manifest (`albumCovers`). A cover
//    is written again if its file went missing or the album's artwork
//    source changed, and removed when its folder no longer holds any
//    managed song (so the empty folder can go too).
//
//  SAFETY
//  The artwork is READ from Apple Music (`LibraryArtworkReader`, read-only
//  ITLibrary) and converted in memory. Nothing is written to the library.
//

import Foundation

/// A cover to write on the card.
struct CoverWrite: Sendable, Hashable, Identifiable {
    /// e.g. `Music/Adele/25/cover.jpg`.
    let path: CardPath
    /// The track whose artwork is used.
    let trackID: PersistentID
    /// Identifies the artwork source, to notice changes later.
    let sourceKey: String
    /// For the preview, e.g. "Adele — 25".
    let albumName: String
    var id: CardPath { path }
}

/// Reads an album's artwork from the library: raw image bytes (JPEG, PNG…).
protocol AlbumArtworkProviding: Sendable {
    /// The artwork image data for a track, or `nil` if there's none.
    func artworkData(for trackID: PersistentID) -> Data?
}

/// Planning covers.
enum AlbumCovers {

    /// The file name Q2 Sync writes.
    static let fileName = "cover.jpg"

    /// Names the Q2 reads as folder artwork. If one of these exists and
    /// isn't Q2 Sync's, the folder is left alone.
    static let artworkNames: Set<String> = [
        "cover.jpg", "cover.jpeg", "cover.png", "cover.webp",
        "folder.jpg", "folder.jpeg", "folder.png", "folder.webp",
    ]

    /// Plans the covers for the songs that will be on the card.
    ///
    /// - Parameters:
    ///   - tracks: Songs that will be on the card after the sync.
    ///   - finalPaths: Each of those songs' card path after the sync.
    ///   - manifest: The card's manifest (for Q2 Sync's own covers).
    ///   - cardFiles: Files now in the Music folder, keyed by `caseKey`.
    /// - Returns: Covers to write (new, missing or changed).
    static func plan(tracks: [Track], finalPaths: [PersistentID: CardPath],
                     manifest: SyncManifest, cardFiles: [String: CardFile]) -> [CoverWrite] {
        // Group songs by album folder (case-insensitive, as FAT is).
        var folders: [String: (folder: CardPath, tracks: [Track])] = [:]
        for track in tracks {
            guard let path = finalPaths[track.id] else { continue }
            let folder = (path as NSString).deletingLastPathComponent
            guard !folder.isEmpty else { continue }
            folders[CardLayout.caseKey(folder), default: (folder, [])].tracks.append(track)
        }

        let ours = Dictionary((manifest.albumCovers ?? [:]).map { (CardLayout.caseKey($0.key), $0.value) },
                              uniquingKeysWith: { first, _ in first })
        var writes: [CoverWrite] = []
        for (_, group) in folders {
            let coverPath = "\(group.folder)/\(fileName)"
            let coverKey = CardLayout.caseKey(coverPath)
            let existing = ours[coverKey]

            // Someone else's artwork in this folder? Leave the folder alone.
            if existing == nil {
                let hasOwnArt = artworkNames.contains { cardFiles[CardLayout.caseKey("\(group.folder)/\($0)")] != nil }
                if hasOwnArt { continue }
            }

            // The first song (by disc and track) that has artwork.
            let ordered = group.tracks.sorted {
                ($0.discNumber, $0.trackNumber, $0.title) < ($1.discNumber, $1.trackNumber, $1.title)
            }
            guard let source = ordered.first(where: { $0.hasArtwork == true }) else { continue }
            let key = sourceKey(for: source)

            if let existing, existing.sourceKey == key, cardFiles[coverKey] != nil { continue }
            writes.append(CoverWrite(path: coverPath, trackID: source.id, sourceKey: key,
                                     albumName: "\(source.effectiveAlbumArtist) — \(source.displayAlbum)"))
        }
        return writes.sorted { SortKey.compare($0.path, $1.path) }
    }

    /// The track and its modification date: changes when the album's first
    /// song changes or is edited in Music (which is when artwork changes).
    static func sourceKey(for track: Track) -> String {
        "\(track.id)@\(Int(track.modifiedDate?.timeIntervalSince1970 ?? 0))"
    }
}
