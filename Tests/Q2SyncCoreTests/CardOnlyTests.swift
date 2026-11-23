//
//  CardOnlyTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Tests for finding card-only music, copying it back to the Mac (with its
//  own guard and duplicate detection), and applying the user's choices.
//
//  SAFETY
//  The "Mac staging folder" and "~/Music" are temp folders. Real Downloads
//  and Music folders are never used.
//

import Foundation
import Testing
@testable import Q2SyncCore

/// Writes a file on the test card, creating folders.
func putOnCard(_ card: TestCard, _ path: String, bytes: Int = 100) throws {
    let url = card.root.appending(path: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data((0..<bytes).map { UInt8($0 % 200) }).write(to: url)
}

@Suite("Card-only finder")
struct CardOnlyFinderTests {

    @Test("Folders taken from one whole-card scan match scanning each folder")
    func oneScan() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        for path in ["Music/A/B/1.mp3", "Music/A/B/._1.mp3", "Music/Live/database.ignore", "music2/x.mp3",
                     "Old Rips/x.mp3", "_explaylist_data/Mix.m3u", ".q2sync/manifest.json", "Podcasts/ep.mp3"] {
            try putOnCard(card, path)
        }
        let whole = CardScanner.scan(folder: "", on: card.fileSystem)
        for folder in ["Music", "_explaylist_data"] {
            #expect(CardScanner.files(in: folder, from: whole) == CardScanner.scan(folder: folder, on: card.fileSystem))
        }
        #expect(CardScanner.files(in: "Music", from: whole).keys.sorted() == ["music/a/b/1.mp3"])
    }

    @Test("Finds unmanaged audio anywhere except reserved items, the app folder and playlists")
    func finds() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        for path in ["Music/A/B/managed.mp3", "Music/Other/manual.flac", "Old Rips/x.mp3", "notes.txt",
                     "Podcasts/ep.mp3", ".q2sync/Trash/2026/Music/y.mp3", "_explaylist_data/Mix.m3u",
                     "Music/A/B/._managed.mp3"] {
            try putOnCard(card, path)
        }
        var manifest = SyncManifest()
        manifest.entries["M"] = makeEntry("Music/A/B/managed.mp3", size: 100)
        let items = CardOnlyFinder.find(allCardFiles: CardScanner.scan(folder: "", on: card.fileSystem),
                                        manifest: manifest, orphanedEntries: [], profile: .q2Pod)
        #expect(items.map(\.path) == ["Music/Other/manual.flac", "Old Rips/x.mp3"])
        #expect(items.allSatisfy { $0.origin == .unmanaged })
    }

    @Test("After an interrupted sync, songs it copied are adopted, not listed as card-only")
    func interruptedSyncNotCardOnly() {
        // The killed sync copied the song but never saved the manifest.
        let track = makeTrack(id: "1", title: "Hello", artist: "Adele", album: "25")
        let path = CardLayout(profile: .q2Pod).preferredPath(for: track)
        let card = [CardFile(path: path, size: track.fileSize),
                    CardFile(path: "Music/Other/manual.mp3", size: 500)]
        let files = Dictionary(card.map { (CardLayout.caseKey($0.path), $0) }, uniquingKeysWith: { a, _ in a })
        let plan = SyncPlanner.plan(selection: resolved([track]), allSelectedIDs: ["1"], manifest: SyncManifest(),
                                    cardFiles: files, layout: CardLayout(profile: .q2Pod))
        #expect(plan.adoptions.map(\.path) == [path])

        let items = CardOnlyFinder.find(allCardFiles: files, manifest: SyncManifest(),
                                        orphanedEntries: plan.orphanedEntries,
                                        adoptedPaths: plan.adoptions.map(\.path), profile: .q2Pod)
        #expect(items.map(\.path) == ["Music/Other/manual.mp3"])
    }

    @Test("Music copied by hand is adopted and moved into place, not copied again")
    func adoptsHandCopiedMusic() {
        let hello = makeTrack(id: "1", title: "Hello", artist: "Adele", album: "25")
        let other = makeTrack(id: "2", title: "Skyfall", artist: "Adele", album: "Skyfall")
        let lost = makeTrack(id: "3", title: "Rumour", artist: "Adele", album: "21")
        let layout = CardLayout(profile: .q2Pod)
        var plan = SyncPlan()
        plan.copies = [hello, other, lost].map {
            CopyOperation(kind: .add, track: $0, destination: layout.preferredPath(for: $0), obsoletePath: nil, reason: nil)
        }
        func item(_ path: String, _ title: String, size: UInt64) -> CardOnlyItem {
            var item = CardOnlyItem(path: path, size: size, origin: .unmanaged, title: title, artist: "adele", album: nil)
            item.durationSeconds = 181
            item.isInLibrary = true
            return item
        }
        plan.cardOnly = [
            item("Music/Adele - Hello.mp3", "HELLO", size: hello.fileSize),   // identical: adopt
            item("Music/Skyfall.mp3", "Skyfall", size: 4_242),                // different encoding: keep
            item("Old Rips/Rumour.mp3", "Rumour", size: lost.fileSize),       // outside Music/: keep
        ]

        let adopted = CardOnlyFinder.adoptIdenticalCopies(in: &plan, musicFolderName: "Music")
        #expect(adopted == 1)
        #expect(plan.adoptions.map(\.path) == ["Music/Adele - Hello.mp3"])
        #expect(plan.moves.map(\.to) == [layout.preferredPath(for: hello)])
        #expect(plan.copies.map(\.track.id) == ["2", "3"])
        #expect(plan.cardOnly.map(\.path) == ["Music/Skyfall.mp3", "Old Rips/Rumour.mp3"])
    }

    @Test("Songs that left the library become card-only, not plain removals")
    func orphans() {
        var manifest = SyncManifest()
        manifest.entries["gone"] = makeEntry("Music/A/B/01 Gone.mp3")
        manifest.entries["desel"] = makeEntry("Music/A/B/02 Deselected.mp3")
        let card = [CardFile(path: "Music/A/B/01 Gone.mp3", size: 1_000),
                    CardFile(path: "Music/A/B/02 Deselected.mp3", size: 1_000)]
        let plan = SyncPlanner.plan(selection: resolved([]), allSelectedIDs: [], manifest: manifest,
                                    cardFiles: Dictionary(card.map { (CardLayout.caseKey($0.path), $0) }, uniquingKeysWith: { a, _ in a }),
                                    libraryIDs: ["desel"], layout: CardLayout(profile: .q2Pod))
        #expect(plan.removals.map(\.trackID) == ["desel"])
        #expect(plan.orphanedEntries.map(\.trackID) == ["gone"])
    }

    @Test("Library matches need title, artist, length within 2 s, and a LOCAL file")
    func libraryMatch() {
        let local = Track(id: "1", title: "Hello", artist: "Adele", albumArtist: nil, album: nil, genre: nil,
                          trackNumber: 1, discNumber: 1, discCount: 1, isCompilation: false, durationSeconds: 295,
                          fileSize: 1, fileURL: nil, fileKind: nil, modifiedDate: nil, availability: .available)
        let cloud = Track(id: "2", title: "Skyfall", artist: "Adele", albumArtist: nil, album: nil, genre: nil,
                          trackNumber: 1, discNumber: 1, discCount: 1, isCompilation: false, durationSeconds: 286,
                          fileSize: 1, fileURL: nil, fileKind: nil, modifiedDate: nil, availability: .cloudOnly)
        let snapshot = LibrarySnapshot(tracks: [local, cloud], playlists: [], mediaFolderURL: nil)
        var items = [
            CardOnlyItem(path: "a.mp3", size: 1, origin: .unmanaged, title: "hello", artist: "ADELE", durationSeconds: 296.5),
            CardOnlyItem(path: "b.mp3", size: 1, origin: .unmanaged, title: "Hello", artist: "Adele", durationSeconds: 200),
            CardOnlyItem(path: "c.mp3", size: 1, origin: .unmanaged, title: "Skyfall", artist: "Adele", durationSeconds: 286),
            CardOnlyItem(path: "d.mp3", size: 1, origin: .unmanaged),
        ]
        CardOnlyFinder.markLibraryMatches(&items, snapshot: snapshot)
        #expect(items.map(\.isInLibrary) == [true, false, false, false])
    }

    @Test("Card-only trash/delete choices count toward the 20% check")
    func fraction() {
        var plan = SyncPlan()
        plan.managedSongsOnCard = 8
        plan.cardOnly = [CardOnlyItem(path: "x.mp3", size: 1, origin: .unmanaged),
                         CardOnlyItem(path: "y.mp3", size: 1, origin: .unmanaged)]
        #expect(plan.removalFraction(cardOnlyActions: ["x.mp3": .delete]) == 0.1)
        #expect(plan.removalFraction(cardOnlyActions: ["x.mp3": .delete, "y.mp3": .moveToMac]) == 0.2)
        #expect(plan.removalFraction(cardOnlyActions: ["x.mp3": .leave]) == 0)
        let both: [CardPath: CardOnlyAction] = ["x.mp3": .delete, "y.mp3": .delete]
        func needsConfirmation(_ plan: SyncPlan) -> Bool {
            SyncSafety.assess(plan: plan, health: .healthy, isFirstSync: false, availableBytes: 10_000_000_000,
                              includeRemovals: false, cardOnlyActions: both).needsLargeRemovalConfirmation
        }
        #expect(!needsConfirmation(plan), "Exactly 20% (2 of 10) doesn't need extra confirmation")
        plan.managedSongsOnCard = 3
        #expect(needsConfirmation(plan), "2 of 5 (40%) does")
    }
}

@Suite("Recovery copier")
struct RecoveryCopierTests {

    /// A copier writing into a temp "Downloads/Q2 Recovered", protecting a temp "Music".
    func makeCopier() throws -> (RecoveryCopier, URL, URL) {
        let home = try makeTempFolder()
        let staging = home.appending(path: "Downloads/Q2 Recovered")
        let music = home.appending(path: "Music")
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        return (RecoveryCopier(stagingFolder: staging, protectedFolders: [music]), staging, home)
    }

    @Test("Copies into the staging folder, keeps the layout, lists it, never overwrites")
    func copies() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let (copier, staging, home) = try makeCopier(); defer { try? FileManager.default.removeItem(at: home) }
        try putOnCard(card, "Music/Artist/Album/01 Song.mp3", bytes: 2_000_000)
        let source = card.root.appending(path: "Music/Artist/Album/01 Song.mp3")

        let first = try copier.copyBack(source: source, cardPath: "Music/Artist/Album/01 Song.mp3")
        let expected = staging.appending(path: "Artist/Album/01 Song.mp3")
        #expect(first == .copied(URL(filePath: PathGuard.realPath(expected.path)!)))
        #expect(try Data(contentsOf: expected) == Data(contentsOf: source))
        #expect(FileManager.default.fileExists(atPath: source.path), "The card file stays")

        // Same file again: recognised as a duplicate.
        let second = try copier.copyBack(source: source, cardPath: "Music/Artist/Album/01 Song.mp3")
        guard case .duplicate = second else { Issue.record("Expected duplicate"); return }

        // A different file with the same name gets " (2)", nothing is overwritten.
        try putOnCard(card, "Elsewhere/Artist/Album/01 Song.mp3", bytes: 50)
        try putOnCard(card, "Music/Artist/Album/01 Song.mp3", bytes: 70)
        _ = try copier.copyBack(source: source, cardPath: "Music/Artist/Album/01 Song.mp3")
        #expect(FileManager.default.fileExists(atPath: staging.appending(path: "Artist/Album/01 Song (2).mp3").path))
        #expect(try Data(contentsOf: expected).count == 2_000_000, "Original copy untouched")

        let list = try String(contentsOf: staging.appending(path: "RECOVERED.txt"), encoding: .utf8)
        #expect(list.contains("Music/Artist/Album/01 Song.mp3"))
    }

    @Test("Destinations outside the staging folder are refused", arguments: [
        "../outside.mp3", "a/../../outside.mp3", "/etc/x", "", "a//b.mp3",
    ])
    func refusesTraversal(path: String) throws {
        let (copier, _, home) = try makeCopier(); defer { try? FileManager.default.removeItem(at: home) }
        #expect(throws: RecoveryError.self) { try copier.checkDestination(path) }
    }

    @Test("A staging folder inside a protected Music folder is refused")
    func refusesMusicFolder() throws {
        let home = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: home) }
        let music = home.appending(path: "Music")
        let copier = RecoveryCopier(stagingFolder: music.appending(path: "Q2 Recovered"), protectedFolders: [music])
        #expect(throws: RecoveryError.self) { try copier.checkDestination("x.mp3") }
    }

    @Test("A symlink in the staging folder can't redirect a copy into Music")
    func refusesSymlink() throws {
        let (copier, staging, home) = try makeCopier(); defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: staging.appending(path: "Sneaky"),
                                                   withDestinationURL: home.appending(path: "Music"))
        #expect(throws: RecoveryError.self) { try copier.checkDestination("Sneaky/x.mp3") }
    }
}

@Suite("Applying card-only choices")
struct CardOnlyExecutorTests {

    @Test("Move to Mac, delete and leave each do exactly that")
    func actions() async throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let home = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: home) }
        let logs = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: logs) }
        let staging = home.appending(path: "Q2 Recovered")
        for name in ["move", "delete", "leave"] { try putOnCard(card, "Old/\(name).mp3") }
        // Plenty of managed songs so the 20% rule isn't triggered.
        var manifest = SyncManifest()
        for i in 0..<20 {
            try putOnCard(card, "Music/A/B/\(i).mp3")
            manifest.entries["\(i)"] = makeEntry("Music/A/B/\(i).mp3", size: 100)
        }

        var plan = SyncPlan()
        plan.managedSongsOnCard = 20
        plan.cardOnly = ["move", "delete", "leave"].map {
            CardOnlyItem(path: "Old/\($0).mp3", size: 100, origin: .unmanaged)
        }
        let options = SyncOptions(cardOnlyActions: ["Old/move.mp3": .moveToMac, "Old/delete.mp3": .delete])
        var executor = SyncExecutor(fileSystem: card.fileSystem, deviceName: "Test", logsDirectory: logs)
        executor.recoveryCopier = RecoveryCopier(stagingFolder: staging, protectedFolders: [fakeHomeMusic])
        let report = await executor.run(plan: plan, manifest: manifest, options: options) { _ in }

        #expect(report.succeeded)
        #expect(report.cardOnlyMovedToMac == 1 && report.cardOnlyRemoved == 1)
        func onCard(_ path: String) -> Bool { FileManager.default.fileExists(atPath: card.root.appending(path: path).path) }
        #expect(!onCard("Old/move.mp3"), "Move to Mac deletes the card file after copying")
        #expect(FileManager.default.fileExists(atPath: staging.appending(path: "Old/move.mp3").path))
        #expect(!onCard("Old/delete.mp3"))
        #expect(onCard("Old/leave.mp3"))
    }

    @Test("Move to Mac leaves the card file when the copy can't be made")
    func moveNeedsCopy() async throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let logs = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: logs) }
        try putOnCard(card, "Old/a.mp3")
        var plan = SyncPlan()
        plan.managedSongsOnCard = 20
        plan.cardOnly = [CardOnlyItem(path: "Old/a.mp3", size: 100, origin: .unmanaged)]
        let executor = SyncExecutor(fileSystem: card.fileSystem, deviceName: "Test", logsDirectory: logs) // no copier
        let report = await executor.run(plan: plan, manifest: SyncManifest(),
                                        options: SyncOptions(cardOnlyActions: ["Old/a.mp3": .moveToMac])) { _ in }
        #expect(report.cardOnlyMovedToMac == 0)
        #expect(FileManager.default.fileExists(atPath: card.root.appending(path: "Old/a.mp3").path))
    }

    @Test("Unconfirmed large card-only deletions are refused by the executor")
    func largeRefused() async throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let logs = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: logs) }
        try putOnCard(card, "Old/a.mp3")
        var plan = SyncPlan()
        plan.cardOnly = [CardOnlyItem(path: "Old/a.mp3", size: 100, origin: .unmanaged)]
        let executor = SyncExecutor(fileSystem: card.fileSystem, deviceName: "Test", logsDirectory: logs)
        let report = await executor.run(plan: plan, manifest: SyncManifest(),
                                        options: SyncOptions(cardOnlyActions: ["Old/a.mp3": .delete])) { _ in }
        #expect(report.cardOnlyRemoved == 0)
        #expect(FileManager.default.fileExists(atPath: card.root.appending(path: "Old/a.mp3").path))
    }

    @Test("A song already in the library (as a local file) isn't copied back or removed")
    func inLibrarySkipped() async throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let home = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: home) }
        let logs = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: logs) }
        try putOnCard(card, "Old/a.mp3")
        var plan = SyncPlan()
        var item = CardOnlyItem(path: "Old/a.mp3", size: 100, origin: .unmanaged)
        item.isInLibrary = true
        plan.cardOnly = [item]
        var executor = SyncExecutor(fileSystem: card.fileSystem, deviceName: "Test", logsDirectory: logs)
        executor.recoveryCopier = RecoveryCopier(stagingFolder: home.appending(path: "R"), protectedFolders: [])
        let report = await executor.run(plan: plan, manifest: SyncManifest(),
                                        options: SyncOptions(cardOnlyActions: ["Old/a.mp3": .moveToMac])) { _ in }
        #expect(report.cardOnlyMovedToMac == 0)
        #expect(!FileManager.default.fileExists(atPath: home.appending(path: "R/Old/a.mp3").path))
        #expect(FileManager.default.fileExists(atPath: card.root.appending(path: "Old/a.mp3").path))
    }
}

@Suite("Card-only choices")
struct CardOnlyChoicesTests {

    let orphan = CardOnlyItem(path: "Music/A/X/1.mp3", size: 1, origin: .removedFromLibrary(trackID: "T1"),
                              title: "One", artist: "A", album: "X")
    let orphan2 = CardOnlyItem(path: "Music/A/X/2.mp3", size: 1, origin: .removedFromLibrary(trackID: "T2"),
                               title: "Two", artist: "A", album: "X")
    let manual = CardOnlyItem(path: "Old/a.mp3", size: 1, origin: .unmanaged)
    var duplicate: CardOnlyItem {
        var item = CardOnlyItem(path: "dup.mp3", size: 1, origin: .unmanaged, title: "Dup")
        item.isInLibrary = true
        return item
    }
    var items: [CardOnlyItem] { [orphan, orphan2, manual, duplicate] }

    @Test("Items fall into the three groups; in-library wins over origin")
    func groups() {
        #expect(items.map(CardOnlyGroup.init) == [.removedFromLibrary, .removedFromLibrary, .unmanaged, .inLibrary])
        #expect(CardOnlyGroup.inLibrary.actions == [.leave, .delete])
    }

    @Test("Everything is left by default")
    func defaults() {
        #expect(CardOnlyChoices().actions(for: items).isEmpty)
    }

    @Test("A group choice covers every file and hides per-file choices")
    func groupChoice() {
        var choices = CardOnlyChoices()
        choices.perFile[orphan.path] = .moveToMac
        choices.setChoice(.all(.delete), for: .removedFromLibrary, items: items)
        #expect(choices.actions(for: items) == [orphan.path: .delete, orphan2.path: .delete])
    }

    @Test("Choose Individually starts on the previous choice and keeps earlier picks")
    func individually() {
        var choices = CardOnlyChoices()
        choices.perFile[orphan.path] = .delete
        choices.setChoice(.all(.moveToMac), for: .removedFromLibrary, items: items)
        choices.setChoice(.individually, for: .removedFromLibrary, items: items)
        #expect(choices.actions(for: items) == [orphan.path: .delete, orphan2.path: .moveToMac])
    }

    @Test("Move to Mac never applies to a song already in the library")
    func noMoveForDuplicates() {
        var choices = CardOnlyChoices()
        choices.perFile[duplicate.path] = .moveToMac
        choices.setChoice(.individually, for: .inLibrary, items: items)
        #expect(choices.actions(for: items).isEmpty)
    }

    @Test("Albums group by folder and album tag, untagged by folder")
    func albums() {
        let albums = CardOnlyAlbum.group(items)
        #expect(albums.map(\.title) == ["X", "Old", "Unknown Album"])
        #expect(albums[0].items.count == 2 && albums[0].displayName == "A — X")
        #expect(albums[1].artist == nil)
    }
}
