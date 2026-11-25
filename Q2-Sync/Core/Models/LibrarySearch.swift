//
//  LibrarySearch.swift
//  Q2-Sync › Core › Models
//
//  PURPOSE
//  The library browser's search: which artists, albums, genres or playlists
//  stay listed for what you typed, and which of their songs are shown.
//
//  HOW IT FITS
//  `LibraryCategoryView` runs it off the main thread as you type (it goes
//  through every song in the library).
//

import Foundation

/// What was typed in the library browser's search field.
struct LibrarySearch: Sendable {

    /// The words to look for. Never empty.
    let words: [String]

    /// - Parameter text: The search field's text.
    /// - Returns: `nil` if there's nothing but spaces: no search.
    init?(_ text: String) {
        words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.isEmpty { return nil }
    }

    /// `true` if every word is in at least one of the fields (different
    /// words may be in different fields). Ignores case and accents.
    func matches(_ fields: [String]) -> Bool {
        words.allSatisfy { word in fields.contains { $0.localizedStandardContains(word) } }
    }

    /// `true` if the song matches by title, artist, album artist or album.
    func matches(_ track: Track) -> Bool {
        matches([track.title, track.displayArtist, track.effectiveAlbumArtist, track.displayAlbum])
    }

    /// The groups a search leaves listed, and the songs to show for each.
    struct Results: Sendable {

        /// The listed groups, whole and in their original order.
        var groups: [TrackGroup] = []

        /// For each group listed only because of its songs (by group ID):
        /// those songs, in the group's order. Groups that matched by name
        /// aren't here.
        var matchingSongs: [String: [PersistentID]] = [:]

        /// The songs to show for a listed group: all of them if its name
        /// matched, otherwise the matching ones.
        func trackIDs(for group: TrackGroup) -> [PersistentID] {
            matchingSongs[group.id] ?? group.trackIDs
        }
    }

    /// Searches one list of the library browser.
    ///
    /// - Parameters:
    ///   - groups: The whole list.
    ///   - snapshot: The library the groups come from.
    ///   - includingSubtitles: Whether a group's subtitle counts as part of
    ///     its name. `true` for albums (the album artist); `false` for
    ///     playlists, whose subtitle is only "Smart Playlist".
    func results(in groups: [TrackGroup], of snapshot: LibrarySnapshot, includingSubtitles: Bool) -> Results {
        // Each song is checked once, however many groups hold it.
        let songs = Set(snapshot.tracks.lazy.filter { matches($0) }.map(\.id))
        var results = Results()
        for group in groups {
            let subtitle = includingSubtitles ? group.subtitle : nil
            if matches([group.title, subtitle].compactMap { $0 }) {
                results.groups.append(group)
                continue
            }
            let found = group.trackIDs.filter(songs.contains)
            if !found.isEmpty {
                results.groups.append(group)
                results.matchingSongs[group.id] = found
            }
        }
        return results
    }
}
