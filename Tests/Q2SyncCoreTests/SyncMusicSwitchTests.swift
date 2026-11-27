//
//  SyncMusicSwitchTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Tests for the "Sync music onto [Q2]" checkbox: old saved selections
//  load with music on and their ticks intact, music off chooses nothing
//  and plans removing only Q2 Sync's songs, the Sync button's "nothing
//  chosen" check across kinds of content, and the Audiobooks search.
//
//  SAFETY
//  In-memory data and temp folders only.
//

import Foundation
import Testing
@testable import Q2SyncCore

@Suite("Sync music on/off")
struct SyncMusicSwitchTests {

    // MARK: - Saved settings

    @Test("A selection saved before the checkbox existed loads with music on and its ticks")
    func oldSelectionLoads() throws {
        let json = #"{"mode":"selectedItems","artistIDs":["artist:adele"],"albumIDs":[],"genreIDs":[],"playlistIDs":["P1"]}"#
        let selection = try JSONDecoder().decode(SyncSelection.self, from: Data(json.utf8))
        #expect(selection.isEnabled)
        #expect(selection.artistIDs == ["artist:adele"])
        #expect(selection.playlistIDs == ["P1"])
    }

    @Test("An old devices.json keeps its ticks and syncs music")
    func oldDeviceFileLoads() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let oldJSON = """
        {
          "ignoredVolumeUUIDs" : [],
          "knownDevices" : [
            {
              "addedDate" : 785000000,
              "bookmarkData" : "AQID",
              "firmware" : "q2Pod",
              "hasCompletedFirstSync" : true,
              "name" : "Q2CARD",
              "volumeUUID" : "OLD-UUID",
              "selection" : { "mode" : "entireLibrary", "artistIDs" : [], "albumIDs" : ["album:a|b"],
                              "genreIDs" : [], "playlistIDs" : [] }
            }
          ]
        }
        """
        try Data(oldJSON.utf8).write(to: folder.appending(path: "devices.json"))

        let device = DeviceStore(directory: folder).device(withUUID: "OLD-UUID")
        #expect(device?.selection?.isEnabled == true)
        #expect(device?.selection?.mode == .entireLibrary)
        #expect(device?.selection?.albumIDs == ["album:a|b"])
    }

    @Test("Music off is saved and reloaded, ticks kept")
    func offRoundTrip() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var device = KnownDevice(volumeUUID: "U", name: "Q2", firmware: .q2Pod, bookmarkData: Data(),
                                 addedDate: .now, hasCompletedFirstSync: false)
        device.selection = SyncSelection(isEnabled: false, mode: .selectedItems, artistIDs: ["artist:x"])
        try DeviceStore(directory: folder).upsert(device)

        let loaded = DeviceStore(directory: folder).device(withUUID: "U")?.selection
        #expect(loaded?.isEnabled == false)
        #expect(loaded?.artistIDs == ["artist:x"])
    }

    @Test("A new Q2 syncs music")
    func newDeviceMusicOn() {
        #expect(SyncSelection().isEnabled)
    }

    @Test("Unticking Sync music is an edit until Apply; ticking it again is no change")
    func offIsAnEdit() {
        var device = KnownDevice(volumeUUID: "U", name: "Q2", firmware: .q2Pod, bookmarkData: Data(),
                                 addedDate: .now, hasCompletedFirstSync: false)
        device.selection = SyncSelection(mode: .entireLibrary)
        var changes = UnappliedChanges()
        changes.edit(device) { $0.music.isEnabled = false }
        #expect(changes.hasChanges(for: device))
        #expect(device.syncSettings.music.isEnabled)
        changes.edit(device) { $0.music.isEnabled = true }
        #expect(!changes.hasChanges(for: device))
    }

    // MARK: - Choosing

    @Test("Music off chooses nothing, even with Entire library")
    func offResolvesToNothing() {
        let snapshot = LibrarySnapshot(tracks: [makeCopyableTrack(id: "1", title: "One")],
                                       playlists: [Playlist(id: "P", name: "Mix", kind: .regular,
                                                            parentID: nil, trackIDs: ["1"])],
                                       mediaFolderURL: nil)
        let result = SelectionResolver.resolve(SyncSelection(isEnabled: false, mode: .entireLibrary), in: snapshot)
        #expect(result.tracksToSync.isEmpty)
        #expect(result.playlists.isEmpty)
        // No library at all (Apple Music unreadable) is fine with music off.
        #expect(SelectionResolver.resolve(SyncSelection(isEnabled: false), in: .empty).tracksToSync.isEmpty)
    }

    @Test("Nothing chosen only when every kind of content chooses nothing")
    func choosesNothingAcrossKinds() {
        let musicOff = SyncSelection(isEnabled: false, mode: .entireLibrary)
        let musicTicked = SyncSelection(mode: .selectedItems, artistIDs: ["artist:x"])
        let booksAll = AudiobookSelection(isEnabled: true, includesAll: true)
        let booksNone = AudiobookSelection(isEnabled: true, includesAll: false)

        #expect(DeviceSyncSettings(music: musicOff, audiobooks: AudiobookSelection()).choosesNothing)
        #expect(DeviceSyncSettings(music: SyncSelection(), audiobooks: booksNone).choosesNothing)
        // Audiobooks only: there's something to sync.
        #expect(!DeviceSyncSettings(music: musicOff, audiobooks: booksAll).choosesNothing)
        #expect(!DeviceSyncSettings(music: musicTicked, audiobooks: AudiobookSelection()).choosesNothing)
    }

    // MARK: - Planning

    @Test("Music off removes Q2 Sync's songs only; card-only songs are untouched")
    func offPlansRemovals() {
        var manifest = SyncManifest()
        manifest.entries["1"] = makeEntry("Music/Artist/Album/01 One.mp3")
        manifest.entries["2"] = makeEntry("Music/Artist/Album/02 Two.mp3")
        let card = [CardFile(path: "Music/Artist/Album/01 One.mp3", size: 1_000),
                    CardFile(path: "Music/Artist/Album/02 Two.mp3", size: 1_000),
                    CardFile(path: "Music/Mine/Hand copied.mp3", size: 5)]
        let selection = SelectionResolver.resolve(SyncSelection(isEnabled: false, mode: .entireLibrary), in: .empty)

        // What SyncCoordinator does with music off: no library IDs, so the
        // songs are removals rather than "missing from the library".
        let plan = SyncPlanner.plan(selection: selection, allSelectedIDs: [], manifest: manifest,
                                    cardFiles: Dictionary(card.map { (CardLayout.caseKey($0.path), $0) },
                                                          uniquingKeysWith: { a, _ in a }),
                                    libraryIDs: nil, layout: CardLayout(profile: .q2Pod))

        #expect(Set(plan.removals.map(\.entry.path)) == ["Music/Artist/Album/01 One.mp3", "Music/Artist/Album/02 Two.mp3"])
        #expect(plan.orphanedEntries.isEmpty)
        #expect(plan.copies.isEmpty)
        #expect(!plan.removals.contains { $0.entry.path == "Music/Mine/Hand copied.mp3" })

        // Auto-sync never applies it on its own.
        guard case .needsReview = AutoSyncPolicy.decide(plan: plan, assessment: SafetyAssessment()) else {
            Issue.record("Music off with songs on the card must stop for review")
            return
        }
    }

    @Test("Music off with audiobooks on still plans the books")
    func offStillPlansAudiobooks() {
        let book = Audiobook(id: "b", title: "Book", author: nil, durationSeconds: 3600,
                             parts: [AudiobookPart(fileURL: URL(filePath: "/b.m4b"), trackNumber: 0, discNumber: 0,
                                                   durationSeconds: 3600, fileSize: 10)],
                             availability: .available)
        let plan = AudiobookPlanner.plan(books: [book], selection: AudiobookSelection(isEnabled: true),
                                         manifest: SyncManifest(), card: AudiobookCardListing(),
                                         folderName: "Audiobooks")
        #expect(plan.copies.count == 1)
    }
}

@Suite("Audiobook search")
struct AudiobookSearchTests {

    private func make(_ title: String, _ author: String?) -> Audiobook {
        Audiobook(id: title, title: title, author: author, durationSeconds: 3600,
                  parts: [AudiobookPart(fileURL: URL(filePath: "/\(title).m4b"), trackNumber: 0, discNumber: 0,
                                        durationSeconds: 3600, fileSize: 10)],
                  availability: .available)
    }

    private var books: [Audiobook] {
        [make("Project Hail Mary", "Andy Weir"), make("Artemis", "Andy Weir"), make("MaddAddam", "Margaret Atwood"),
         make("Café Stories", nil)]
    }

    @Test("Matches title or author, ignoring case, in the given order")
    func matches() {
        #expect(AudiobookSearch.filter(books, matching: "weir").map(\.title) == ["Project Hail Mary", "Artemis"])
        #expect(AudiobookSearch.filter(books, matching: "ADDAM").map(\.title) == ["MaddAddam"])
    }

    @Test("Ignores accents; blank text shows every book")
    func accentsAndBlank() {
        #expect(AudiobookSearch.filter(books, matching: "cafe").map(\.title) == ["Café Stories"])
        #expect(AudiobookSearch.filter(books, matching: "  ").count == books.count)
        #expect(AudiobookSearch.filter(books, matching: "zzz").isEmpty)
    }
}
