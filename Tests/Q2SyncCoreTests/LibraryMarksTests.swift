//
//  LibraryMarksTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Tests for the library browser's marks (can sync / on Q2 / next sync)
//  and for the Mac-side record of a card's contents they come from.
//
//  SAFETY
//  In-memory snapshots and temp folders only.
//

import Foundation
import Testing
@testable import Q2SyncCore

@Suite("Library marks")
struct LibraryMarksTests {

    /// a1, a2 copyable; a3 cloud-only; b1 copyable; b2 protected.
    /// Playlist "Mix" lists a1 twice and a3.
    let snapshot = LibrarySnapshot(tracks: [
        makeTrack(id: "a1", artist: "Adele", albumArtist: "Adele", album: "25", genre: "Pop", track: 1),
        makeTrack(id: "a2", artist: "Adele", albumArtist: "Adele", album: "25", genre: "Pop", track: 2),
        makeTrack(id: "a3", artist: "Adele", albumArtist: "Adele", album: "25", genre: "Pop", track: 3,
                  availability: .cloudOnly),
        makeTrack(id: "b1", artist: "Band", albumArtist: "Band", album: "Live", genre: "Rock"),
        makeTrack(id: "b2", artist: "Band", albumArtist: "Band", album: "Live", genre: "Rock", track: 2,
                  availability: .drmProtected),
    ], playlists: [
        Playlist(id: "P1", name: "Mix", kind: .regular, parentID: nil, trackIDs: ["a1", "a1", "a3"]),
    ], mediaFolderURL: nil)

    func record(_ ids: [PersistentID]) -> CardContentsRecord {
        var manifest = SyncManifest()
        for id in ids {
            manifest.entries[id] = SyncManifest.Entry(path: "Music/\(id).mp3", sourceSize: 1, sourceModified: nil,
                                                      cardSize: 1, syncedAt: .now, title: id, artist: nil, album: nil)
        }
        return CardContentsRecord(volumeUUID: "ABCD-1234", manifest: manifest)
    }

    @Test("Without a Q2, only songs that can't be copied are marked")
    func noQ2() {
        let marks = LibraryMarks(snapshot: snapshot, record: nil, selection: nil)
        #expect(!marks.hasQ2)
        #expect(marks.placement(of: "a1") == nil)
        #expect(marks.placement(of: "a3") == .cantSync)
        #expect(marks.placement(of: "b2") == .cantSync)
        #expect(marks.marks(for: ["a1", "a2", "a3"]) == GroupMarks(total: 3, syncable: 2, onQ2: 0, nextSync: 0))
    }

    @Test("On Q2, next sync and not chosen come from the record and the selection")
    func withQ2() {
        let selection = SyncSelection(mode: .entireLibrary)
        let marks = LibraryMarks(snapshot: snapshot, record: record(["a1"]), selection: selection)
        #expect(marks.hasQ2)
        #expect(marks.placement(of: "a1") == .onQ2)
        #expect(marks.placement(of: "a2") == .nextSync)
        #expect(marks.placement(of: "a3") == .cantSync)
        #expect(marks.marks(for: ["a1", "a2", "a3"]) == GroupMarks(total: 3, syncable: 2, onQ2: 1, nextSync: 1))

        var none = SyncSelection()
        none.mode = .selectedItems
        let unchosen = LibraryMarks(snapshot: snapshot, record: record(["a1"]), selection: none)
        #expect(unchosen.placement(of: "a2") == .notChosen)
        #expect(unchosen.placement(of: "b1") == .notChosen)
    }

    @Test("A song on the card stays marked On Q2 even if it can't be copied any more")
    func onCardButNotCopyable() {
        let marks = LibraryMarks(snapshot: snapshot, record: record(["a3"]), selection: nil)
        #expect(marks.placement(of: "a3") == .onQ2)
    }

    @Test("Duplicate playlist entries count once")
    func duplicates() {
        let marks = LibraryMarks(snapshot: snapshot, record: record(["a1"]), selection: nil)
        #expect(marks.marks(for: ["a1", "a1", "a3"]) == GroupMarks(total: 2, syncable: 1, onQ2: 1, nextSync: 0))
    }
}

@Suite("Card contents record")
struct CardContentsStoreTests {

    func tempStore() -> CardContentsStore {
        CardContentsStore(directory: FileManager.default.temporaryDirectory
            .appending(path: "CardContents-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    @Test("Saves, loads and removes a record")
    func roundTrip() throws {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var manifest = SyncManifest()
        manifest.updatedAt = Date(timeIntervalSince1970: 1_000_000)
        manifest.entries["X1"] = SyncManifest.Entry(path: "Music/x.mp3", sourceSize: 1, sourceModified: nil,
                                                    cardSize: 1, syncedAt: .now, title: "X", artist: nil, album: nil)
        let record = CardContentsRecord(volumeUUID: "0A1B-2C3D", manifest: manifest,
                                        checkedAt: Date(timeIntervalSince1970: 2_000_000))
        store.save(record)
        #expect(store.load(volumeUUID: "0A1B-2C3D") == record)
        store.remove(volumeUUID: "0A1B-2C3D")
        #expect(store.load(volumeUUID: "0A1B-2C3D") == nil)
    }

    @Test("Holds only song IDs and dates, no titles or paths")
    func noPersonalDetails() throws {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var manifest = SyncManifest()
        manifest.entries["X1"] = SyncManifest.Entry(path: "Music/Secret Song.mp3", sourceSize: 1, sourceModified: nil,
                                                    cardSize: 1, syncedAt: .now, title: "Secret Song",
                                                    artist: "Someone", album: nil)
        store.save(CardContentsRecord(volumeUUID: "ABCD", manifest: manifest))
        let text = try String(contentsOf: store.directory.appending(path: "ABCD.json"), encoding: .utf8)
        #expect(!text.contains("Secret"))
        #expect(!text.contains("Someone"))
    }

    @Test("A UUID that isn't hex and dashes can't name a file")
    func rejectsOddUUIDs() {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var manifest = SyncManifest()
        manifest.updatedAt = .now
        for bad in ["../evil", "", "ABCD/EF", "nope"] {
            store.save(CardContentsRecord(volumeUUID: bad, manifest: manifest))
            #expect(store.load(volumeUUID: bad) == nil)
        }
        #expect(!FileManager.default.fileExists(atPath: store.directory.path))
    }
}

@Suite("Song list CSV and missing-file reasons")
struct SongListCSVTests {

    @Test("Fields with commas, quotes or line breaks are quoted")
    func escaping() {
        #expect(SongListCSV.escape("plain") == "plain")
        #expect(SongListCSV.escape("a, b") == "\"a, b\"")
        #expect(SongListCSV.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
    }

    @Test("Durations read like a player")
    func durations() {
        #expect(SongListCSV.duration(225) == "3:45")
        #expect(SongListCSV.duration(3723) == "1:02:03")
    }

    @Test("Only songs on the Q2 or chosen for it are listed, with their status")
    func rows() {
        let snapshot = LibrarySnapshot(tracks: [
            makeTrack(id: "a", title: "One, Two", album: "A", track: 1),
            makeTrack(id: "b", title: "Next", album: "A", track: 2),
            makeTrack(id: "c", title: "Skipped", album: "A", track: 3),
        ], playlists: [Playlist(id: "P", name: "Next", kind: .regular, parentID: nil, trackIDs: ["b"])],
                                    mediaFolderURL: nil)
        var manifest = SyncManifest()
        manifest.entries["a"] = SyncManifest.Entry(path: "Music/a.m4a", sourceSize: 1, sourceModified: nil,
                                                   cardSize: 1, syncedAt: .now, title: "a", artist: nil, album: nil)
        var selection = SyncSelection()
        selection.mode = .selectedItems
        selection.playlistIDs = ["P"]
        let marks = LibraryMarks(snapshot: snapshot, record: CardContentsRecord(volumeUUID: "ABCD-1234", manifest: manifest),
                                 selection: selection)
        let lines = SongListCSV.make(snapshot: snapshot, marks: marks).split(separator: "\r\n")
        #expect(lines.count == 3)
        #expect(lines[1].hasPrefix("On Q2,\"One, Two\""))
        #expect(lines[2].hasPrefix("Next sync,Next"))
    }

    @Test("A missing file says where it went")
    func missingReasons() throws {
        let trash = URL(filePath: "/Users/x/.Trash/song.mp3")
        #expect(Track.missingFileReason(for: trash) == "In the Trash")

        let drive = URL(filePath: "/Volumes/NoSuchDrive-Q2Sync/Music/song.mp3")
        #expect(Track.missingFileReason(for: drive).contains("NoSuchDrive-Q2Sync"))
        #expect(Track.missingFileReason(for: drive).contains("isn't connected"))

        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(Track.missingFileReason(for: folder.appending(path: "gone.mp3")).hasPrefix("Moved or renamed"))
        #expect(Track.missingFileReason(for: folder.appending(path: "no/gone.mp3")).hasPrefix("Moved or deleted"))
        #expect(Track.missingFileReason(for: nil) == "File not found on disk")
    }
}
