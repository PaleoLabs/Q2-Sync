//
//  LibrarySearchTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Tests for the library browser's search: which groups stay listed and
//  which of their songs are shown.
//
//  SAFETY
//  In-memory snapshots only.
//

import Foundation
import Testing
@testable import Q2SyncCore

@Suite("Library search")
struct LibrarySearchTests {

    let snapshot = LibrarySnapshot(tracks: [
        makeTrack(id: "a1", title: "Hello", artist: "Adele", albumArtist: "Adele", album: "25",
                  genre: "Pop", track: 1),
        makeTrack(id: "a2", title: "Water Under the Bridge", artist: "Adele", albumArtist: "Adele", album: "25",
                  genre: "Pop", track: 2),
        makeTrack(id: "b1", title: "Jóga", artist: "Björk", albumArtist: "Björk", album: "Homogenic",
                  genre: "Electronic"),
        makeTrack(id: "c1", title: "Hello Again", artist: "Cars", albumArtist: "Various", album: "Mixed",
                  genre: "Rock"),
    ], playlists: [], mediaFolderURL: nil)

    func artists(_ text: String) throws -> LibrarySearch.Results {
        let query = try #require(LibrarySearch(text))
        return query.results(in: snapshot.artistGroups, of: snapshot, includingSubtitles: true)
    }

    func shown(_ results: LibrarySearch.Results) -> [String: [PersistentID]] {
        Dictionary(uniqueKeysWithValues: results.groups.map { ($0.title, results.trackIDs(for: $0)) })
    }

    @Test("Nothing but spaces is no search")
    func blank() {
        #expect(LibrarySearch("") == nil)
        #expect(LibrarySearch("   ") == nil)
    }

    @Test("A group matched by name shows all its songs")
    func byName() throws {
        let results = try artists("adele")
        #expect(shown(results) == ["Adele": ["a1", "a2"]])
        #expect(results.matchingSongs.isEmpty)
    }

    @Test("A group matched only by its songs shows just those, in list order")
    func bySong() throws {
        let results = try artists("hello")
        #expect(results.groups.map(\.title) == ["Adele", "Cars"])
        #expect(shown(results) == ["Adele": ["a1"], "Cars": ["c1"]])
    }

    @Test("Songs match by artist, album artist and album, but not genre")
    func fields() throws {
        #expect(shown(try artists("various")) == ["Cars": ["c1"]])
        #expect(shown(try artists("homogenic")) == ["Björk": ["b1"]])
        #expect(try artists("electronic").groups.isEmpty)
    }

    @Test("Every word must match, in any order and across fields; case and accents don't matter")
    func words() throws {
        #expect(shown(try artists("  BRIDGE adele ")) == ["Adele": ["a2"]])
        #expect(shown(try artists("bjork joga")) == ["Björk": ["b1"]])
        #expect(try artists("adele joga").groups.isEmpty)
    }

    @Test("A subtitle counts as part of the name only when asked")
    func subtitles() throws {
        let groups = [TrackGroup(id: "playlist:P1", title: "Mix", subtitle: "Smart Playlist", trackIDs: ["a1"])]
        let query = try #require(LibrarySearch("smart"))
        #expect(query.results(in: groups, of: snapshot, includingSubtitles: false).groups.isEmpty)
        #expect(query.results(in: groups, of: snapshot, includingSubtitles: true).groups == groups)
    }
}
