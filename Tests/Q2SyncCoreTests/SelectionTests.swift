//
//  SelectionTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Tests for turning a checkbox selection into the tracks and playlists to
//  sync, and for saving selections with each device.
//
//  SAFETY
//  In-memory snapshots and temp folders only.
//

import Foundation
import Testing
@testable import Q2SyncCore

@Suite("Selection resolver")
struct SelectionResolverTests {

    /// A small library:
    ///   Adele / 25:        a1, a2 (Pop)      a3 cloud-only (Pop)
    ///   Band / Live:       b1 (Rock), b2 DRM (Rock)
    ///   Solo / Demo:       s1 (Jazz)
    ///   Playlist "Mix":    s1, a1, s1 (duplicate entry)
    ///   Smart "Rocky":     b1
    let snapshot = LibrarySnapshot(tracks: [
        makeTrack(id: "a1", artist: "Adele", albumArtist: "Adele", album: "25", genre: "Pop", track: 1),
        makeTrack(id: "a2", artist: "Adele", albumArtist: "Adele", album: "25", genre: "Pop", track: 2),
        makeTrack(id: "a3", artist: "Adele", albumArtist: "Adele", album: "25", genre: "Pop", track: 3,
                  availability: .cloudOnly),
        makeTrack(id: "b1", artist: "Band", albumArtist: "Band", album: "Live", genre: "Rock"),
        makeTrack(id: "b2", artist: "Band", albumArtist: "Band", album: "Live", genre: "Rock", track: 2,
                  availability: .drmProtected),
        makeTrack(id: "s1", artist: "Solo", albumArtist: "Solo", album: "Demo", genre: "Jazz"),
    ], playlists: [
        Playlist(id: "P1", name: "Mix", kind: .regular, parentID: "F1", trackIDs: ["s1", "a1", "s1"]),
        Playlist(id: "P2", name: "Rocky", kind: .smart, parentID: nil, trackIDs: ["b1"]),
        Playlist(id: "F1", name: "Folder", kind: .folder, parentID: nil, trackIDs: []),
    ], mediaFolderURL: nil)

    @Test("Nothing ticked means nothing to sync")
    func emptySelection() {
        let result = SelectionResolver.resolve(SyncSelection(), in: snapshot)
        #expect(result.tracksToSync.isEmpty)
        #expect(result.skippedTracks.isEmpty)
        #expect(result.playlists.isEmpty)
        #expect(SyncSelection().isEmpty)
    }

    @Test("Entire library includes every copyable track and every non-folder playlist")
    func entireLibrary() {
        let result = SelectionResolver.resolve(SyncSelection(mode: .entireLibrary), in: snapshot)
        #expect(Set(result.tracksToSync.map(\.id)) == ["a1", "a2", "b1", "s1"])
        #expect(Set(result.skippedTracks.map(\.id)) == ["a3", "b2"])
        #expect(result.playlists.map(\.name) == ["Mix", "Rocky"])
    }

    @Test("Ticked items combine as a union, without duplicates")
    func union() {
        var selection = SyncSelection()
        selection.artistIDs = ["artist:adele"]
        selection.genreIDs = ["genre:jazz"]
        selection.playlistIDs = ["P1"] // overlaps with both
        let result = SelectionResolver.resolve(selection, in: snapshot)
        #expect(result.tracksToSync.map(\.id) == ["a1", "a2", "s1"], "Union, deduplicated, album order")
        #expect(result.skippedTracks.map(\.id) == ["a3"])
        #expect(result.playlists.map(\.id) == ["P1"])
    }

    @Test("Albums are matched by album artist and album name")
    func album() {
        var selection = SyncSelection()
        selection.albumIDs = ["album:band|live"]
        let result = SelectionResolver.resolve(selection, in: snapshot)
        #expect(result.tracksToSync.map(\.id) == ["b1"])
        #expect(result.skippedCounts[.drmProtected] == 1)
    }

    @Test("Ticked items that left the library are counted and ignored")
    func missingItems() {
        var selection = SyncSelection()
        selection.artistIDs = ["artist:adele", "artist:deleted band"]
        selection.playlistIDs = ["GONE"]
        let result = SelectionResolver.resolve(selection, in: snapshot)
        #expect(result.missingSelectionCount == 2)
        #expect(result.tracksToSync.count == 2)
    }

    @Test("Folder playlists are never written, even if their ID was saved")
    func folderIgnored() {
        var selection = SyncSelection()
        selection.playlistIDs = ["F1"]
        let result = SelectionResolver.resolve(selection, in: snapshot)
        #expect(result.playlists.isEmpty)
        #expect(result.missingSelectionCount == 1)
    }

    @Test("Total size adds up the copyable tracks only")
    func totalSize() {
        let result = SelectionResolver.resolve(SyncSelection(mode: .entireLibrary), in: snapshot)
        #expect(result.totalBytes == 4 * 1_000)
    }
}

@Suite("Selection persistence")
struct SelectionPersistenceTests {

    @Test("A device's selection is saved and reloaded")
    func roundTrip() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        var selection = SyncSelection()
        selection.albumIDs = ["album:adele|25"]
        selection.playlistIDs = ["P1"]
        var device = KnownDevice(volumeUUID: "U", name: "Q2", firmware: .q2Pod, bookmarkData: Data(),
                                 addedDate: .now, hasCompletedFirstSync: false)
        device.selection = selection
        try DeviceStore(directory: folder).upsert(device)

        #expect(DeviceStore(directory: folder).device(withUUID: "U")?.selection == selection)
    }

    @Test("devices.json saved before selections existed still loads")
    func oldFormatLoads() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        // Exactly the shape early versions wrote: no "selection" key.
        let oldJSON = """
        {
          "ignoredVolumeUUIDs" : [],
          "knownDevices" : [
            {
              "addedDate" : 785000000,
              "bookmarkData" : "AQID",
              "firmware" : "q2Pod",
              "hasCompletedFirstSync" : false,
              "name" : "Q2CARD",
              "volumeUUID" : "OLD-UUID"
            }
          ]
        }
        """
        try Data(oldJSON.utf8).write(to: folder.appending(path: "devices.json"))

        let device = DeviceStore(directory: folder).device(withUUID: "OLD-UUID")
        #expect(device != nil, "Old devices must not be forgotten after an update")
        #expect(device?.selection == nil)
        #expect(device?.effectiveSelection.isEmpty == true)
    }
}

@Suite("Unapplied changes (Revert / Apply)")
struct UnappliedChangesTests {

    /// A Q2 with one artist ticked and saved.
    private func device(uuid: String = "U") -> KnownDevice {
        var device = KnownDevice(volumeUUID: uuid, name: "Q2", firmware: .q2Pod, bookmarkData: Data(),
                                 addedDate: .now, hasCompletedFirstSync: false)
        device.selection = SyncSelection(mode: .selectedItems, artistIDs: ["artist:ac/dc"])
        return device
    }

    @Test("With no edits, the saved settings are shown and there's nothing to apply")
    func noEdits() {
        let changes = UnappliedChanges()
        let q2 = device()
        #expect(changes.settings(for: q2) == q2.syncSettings)
        #expect(!changes.hasChanges(for: q2))
        #expect(changes.changes(for: q2) == nil)
    }

    @Test("A tick is shown but not saved until applied")
    func editIsPending() {
        var changes = UnappliedChanges()
        let q2 = device()
        changes.edit(q2) { $0.music.artistIDs.insert("artist:adele") }
        #expect(changes.hasChanges(for: q2))
        #expect(changes.settings(for: q2).music.artistIDs == ["artist:ac/dc", "artist:adele"])
        #expect(q2.syncSettings.music.artistIDs == ["artist:ac/dc"], "Saved settings untouched")
        #expect(changes.changes(for: q2)?.music.artistIDs.contains("artist:adele") == true)
    }

    @Test("Ticking then unticking the same box counts as no change")
    func backToSavedIsNoChange() {
        var changes = UnappliedChanges()
        let q2 = device()
        changes.edit(q2) { $0.music.artistIDs.insert("artist:adele") }
        changes.edit(q2) { $0.music.artistIDs.remove("artist:adele") }
        #expect(!changes.hasChanges(for: q2))
    }

    @Test("Switching to Entire library is an edit too")
    func modeChange() {
        var changes = UnappliedChanges()
        let q2 = device()
        changes.edit(q2) { $0.music.mode = .entireLibrary }
        #expect(changes.hasChanges(for: q2))
        #expect(changes.settings(for: q2).music.mode == .entireLibrary)
    }

    @Test("Revert puts the saved settings back")
    func revert() {
        var changes = UnappliedChanges()
        let q2 = device()
        changes.edit(q2) { $0.music.artistIDs.insert("artist:adele") }
        changes.discard(volumeUUID: q2.volumeUUID)
        #expect(!changes.hasChanges(for: q2))
        #expect(changes.settings(for: q2) == q2.syncSettings)
    }

    @Test("Once the edits are saved, they're no longer unapplied")
    func appliedMatchesSaved() {
        var changes = UnappliedChanges()
        var q2 = device()
        changes.edit(q2) { $0.music.artistIDs.insert("artist:adele") }
        q2.selection = changes.changes(for: q2)?.music // What Apply saves.
        #expect(!changes.hasChanges(for: q2))
    }

    @Test("Each Q2 keeps its own edits; leaving throws all away")
    func perDevice() {
        var changes = UnappliedChanges()
        let first = device(uuid: "A"), second = device(uuid: "B")
        changes.edit(first) { $0.music.artistIDs.insert("artist:adele") }
        #expect(changes.hasChanges(for: first))
        #expect(!changes.hasChanges(for: second))
        changes.discardAll()
        #expect(!changes.hasChanges(for: first))
    }
}
