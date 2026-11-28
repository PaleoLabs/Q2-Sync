//
//  PodcastTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Tests for podcasts (issue #20): reading the Podcasts app's downloads
//  and database, the selection, the path guard's `Podcasts/` exception
//  and the planner.
//
//  SAFETY
//  Uses temporary folders and a database built here; never the real
//  Podcasts app or a real card.
//

import Foundation
import SQLite3
import Testing
@testable import Q2SyncCore

// MARK: - Helpers

/// 2024-10-07 12:00 UTC, as seconds since 2001 (`ZPUBDATE`).
private let oct7: Double = 749_995_200

private func episode(_ id: String, show: String = "show-a", showTitle: String = "The Daily",
                     title: String = "Episode", published: Double? = oct7, size: UInt64 = 10,
                     ext: String = "mp3", kind: PodcastEpisodeKind = .audio,
                     state: PodcastPlayState = .unplayed, protected: Bool = false,
                     folder: URL = URL(filePath: "/tmp/podcasts")) -> PodcastEpisode {
    PodcastEpisode(id: id, showID: show, showTitle: showTitle, title: title,
                   published: published.map { Date(timeIntervalSinceReferenceDate: $0) },
                   fileURL: folder.appending(path: "\(id).\(ext)"), fileSize: size, kind: kind,
                   playState: state, isProtected: protected)
}

private func show(_ episodes: [PodcastEpisode]) -> PodcastShow {
    PodcastShow(id: episodes[0].showID, title: episodes[0].showTitle, author: nil, episodes: episodes)
}

private let utc = TimeZone(identifier: "UTC")!
private let allShows = PodcastSelection(isEnabled: true)

private func plan(_ shows: [PodcastShow], _ selection: PodcastSelection = allShows, card: TestCard,
                  manifest: SyncManifest = SyncManifest()) -> PodcastPlan {
    PodcastPlanner.plan(shows: shows, selection: selection, manifest: manifest,
                        card: CardFolderListing.scan(folderName: "Podcasts", on: card.fileSystem),
                        folderName: "Podcasts", timeZone: utc)
}

private func write(_ card: TestCard, _ path: String, bytes: Int) throws {
    let url = card.root.appending(path: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: url)
}

private func record(_ path: String, show: String = "show-a", size: UInt64 = 10) -> PodcastEpisodeRecord {
    PodcastEpisodeRecord(path: path, showID: show, showTitle: "The Daily", title: "Episode",
                         sourceSize: size, cardSize: size, syncedAt: .now)
}

/// Builds a small `MTLibrary.sqlite` with the columns Q2 Sync reads.
private func makeDatabase(at url: URL, shows: [(pk: Int, uuid: String, title: String)],
                          episodes: [(uuid: String, show: Int, title: String, pub: Double?, state: Int, drm: String?)]) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var db: OpaquePointer?
    #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    func exec(_ sql: String) { #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "\(sql)") }
    func quoted(_ s: String?) -> String { s.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" } ?? "NULL" }
    exec("CREATE TABLE ZMTPODCAST (Z_PK INTEGER PRIMARY KEY, ZUUID VARCHAR, ZTITLE VARCHAR, ZAUTHOR VARCHAR)")
    exec("CREATE TABLE ZMTEPISODE (Z_PK INTEGER PRIMARY KEY, ZUUID VARCHAR, ZTITLE VARCHAR, ZPUBDATE TIMESTAMP, ZPLAYSTATE INTEGER, ZDRMKEYURI VARCHAR, ZPODCAST INTEGER, ZPLAYCOUNT INTEGER)")
    for s in shows {
        exec("INSERT INTO ZMTPODCAST VALUES (\(s.pk), \(quoted(s.uuid)), \(quoted(s.title)), 'Author')")
    }
    for e in episodes {
        exec("INSERT INTO ZMTEPISODE (ZUUID, ZTITLE, ZPUBDATE, ZPLAYSTATE, ZDRMKEYURI, ZPODCAST, ZPLAYCOUNT) VALUES (\(quoted(e.uuid)), \(quoted(e.title)), \(e.pub.map { String($0) } ?? "NULL"), \(e.state), \(quoted(e.drm)), \(e.show), 0)")
    }
}

// MARK: - Reading

@Suite("Podcasts: reading the Podcasts app")
struct PodcastReaderTests {

    @Test("Downloads are joined with the database; shows sorted, newest episode first")
    func readsLibrary() async throws {
        let folder = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appending(path: ApplePodcastsSource.downloadsPath)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        for (name, bytes) in [("E1.mp3", 3), ("E2.mp3", 5), ("E3.m4v", 7), ("E4.mp3", 2), ("notes.txt", 1), (".E5.mp3", 1)] {
            try Data(repeating: 0, count: bytes).write(to: cache.appending(path: name))
        }
        try makeDatabase(at: folder.appending(path: ApplePodcastsSource.databasePath),
                         shows: [(1, "S-B", "Zebra Talk"), (2, "S-A", "art of things")],
                         episodes: [("E1", 1, "Old", oct7, 0, nil),
                                    ("E2", 1, "New", oct7 + 86_400, 1, nil),
                                    ("E3", 2, "A video", oct7, 2, nil),
                                    // E4 has no row: left out. E9 isn't downloaded: left out.
                                    ("E9", 2, "Not downloaded", oct7, 2, nil)])

        let shows = try await ApplePodcastsSource(folder: folder).loadPodcasts()
        #expect(shows.map(\.title) == ["art of things", "Zebra Talk"])
        #expect(shows[0].episodes.map(\.kind) == [.video])
        let zebra = shows[1]
        #expect(zebra.id == "S-B" && zebra.author == "Author")
        #expect(zebra.episodes.map(\.title) == ["New", "Old"])
        #expect(zebra.episodes.map(\.playState) == [.inProgress, .played])
        #expect(zebra.episodes.map(\.fileSize) == [5, 3])
        #expect(zebra.episodes[1].published == Date(timeIntervalSinceReferenceDate: oct7))
        #expect(zebra.totalSize == 8)
    }

    @Test("A protected episode is marked and can't sync")
    func protectedEpisode() async throws {
        let folder = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appending(path: ApplePodcastsSource.downloadsPath)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data([1]).write(to: cache.appending(path: "P1.mp3"))
        try makeDatabase(at: folder.appending(path: ApplePodcastsSource.databasePath),
                         shows: [(1, "S", "Show")], episodes: [("P1", 1, "Bonus", nil, 2, "skd://key")])
        let shows = try await ApplePodcastsSource(folder: folder).loadPodcasts()
        let only = try #require(shows.first?.episodes.first)
        #expect(only.isProtected && !only.canSync)
        #expect(only.published == nil)
    }

    @Test("Nothing downloaded is an empty list, even without a database")
    func nothingDownloaded() async throws {
        let folder = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        #expect(try await ApplePodcastsSource(folder: folder).loadPodcasts().isEmpty)
    }

    @Test("Downloads but no database is an error")
    func noDatabase() async throws {
        let folder = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appending(path: ApplePodcastsSource.downloadsPath)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data([1]).write(to: cache.appending(path: "E1.mp3"))
        await #expect(throws: PodcastError.noDatabase) { try await ApplePodcastsSource(folder: folder).loadPodcasts() }
    }

    @Test("The database is opened read-only")
    func readOnly() throws {
        let folder = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "db.sqlite")
        try makeDatabase(at: url, shows: [(1, "S", "Show")], episodes: [("E1", 1, "One", oct7, 2, nil)])
        let before = try Data(contentsOf: url)
        let rows = try PodcastDatabase.rows(at: url, episodeIDs: ["E1", "nope"])
        #expect(rows.count == 1 && rows[0].showTitle == "Show" && rows[0].playState == 2)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test("A link in the downloads folder is never read")
    func links() throws {
        let folder = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let outside = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: outside) }
        let cache = folder.appending(path: ApplePodcastsSource.downloadsPath)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data([1]).write(to: outside.appending(path: "secret.mp3"))
        try FileManager.default.createSymbolicLink(at: cache.appending(path: "L1.mp3"),
                                                   withDestinationURL: outside.appending(path: "secret.mp3"))
        try Data([1]).write(to: cache.appending(path: "E1.mp3"))
        #expect(try PodcastDownloads.list(in: cache, folder: folder).map(\.id) == ["E1"])
    }

    @Test("Play states and kinds")
    func states() {
        #expect(PodcastPlayState(databaseValue: 0) == .played)
        #expect(PodcastPlayState(databaseValue: 1) == .inProgress)
        #expect(PodcastPlayState(databaseValue: 2) == .unplayed)
        #expect(PodcastPlayState(databaseValue: nil) == .unplayed)
        #expect(PodcastEpisodeKind(fileExtension: "MP3") == .audio)
        #expect(PodcastEpisodeKind(fileExtension: "m4a") == .audio)
        #expect(PodcastEpisodeKind(fileExtension: "mp4") == .video)
        #expect(PodcastEpisodeKind(fileExtension: "txt") == nil)
    }

    @Test("Search matches shows, authors and episode titles")
    func search() {
        let daily = show([episode("1", title: "Elections"), episode("2", title: "Weather")])
        #expect(PodcastSearch.filter([daily], matching: "daily").first?.episodes.count == 2)
        #expect(PodcastSearch.filter([daily], matching: "élect").first?.episodes.map(\.id) == ["1"])
        #expect(PodcastSearch.filter([daily], matching: "sports").isEmpty)
        #expect(PodcastSearch.filter([daily], matching: " ").count == 1)
    }
}

// MARK: - Selection

@Suite("Podcasts: selection")
struct PodcastSelectionTests {

    @Test("Unplayed only skips played episodes but keeps ones in progress")
    func unplayedOnly() {
        var selection = PodcastSelection(isEnabled: true, unplayedOnly: true)
        #expect(!selection.includes(episode("1", state: .played)))
        #expect(selection.includes(episode("2", state: .inProgress)))
        #expect(selection.includes(episode("3", state: .unplayed)))
        selection.unplayedOnly = false
        #expect(selection.includes(episode("1", state: .played)))
    }

    @Test("Video, protected, unticked shows and podcasts off are never included")
    func exclusions() {
        let on = PodcastSelection(isEnabled: true, includesAll: false, showIDs: ["show-a"])
        #expect(on.includes(episode("1")))
        #expect(!on.includes(episode("2", show: "show-b")))
        #expect(!on.includes(episode("3", ext: "m4v", kind: .video)))
        #expect(!on.includes(episode("4", protected: true)))
        #expect(!PodcastSelection().includes(episode("5")))
        #expect(PodcastSelection(isEnabled: true, includesAll: false).choosesNothing)
        #expect(!on.choosesNothing)
    }

    @Test("Old saved settings decode with defaults")
    func decoding() throws {
        let decoded = try JSONDecoder().decode(PodcastSelection.self, from: Data(#"{"isEnabled":true}"#.utf8))
        #expect(decoded == PodcastSelection(isEnabled: true))
    }
}

// MARK: - Path guard

@Suite("Podcasts on the card: path guard")
struct PodcastGuardTests {

    @Test("Q2 Pod: show folders and audio files directly inside them are allowed")
    func allowed() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let g = card.pathGuard
        _ = try g.check("Podcasts", for: .createDirectory)
        _ = try g.check("Podcasts/The Daily", for: .createDirectory)
        _ = try g.check("Podcasts/The Daily/2024-10-07 - The Election.mp3", for: .write)
        _ = try g.check("Podcasts/The Daily/2024-10-07 - The Election.mp3", for: .delete)
        _ = try g.check("Podcasts/The Daily", for: .delete)
    }

    @Test("Anything else in Podcasts is refused", arguments: [
        ("Podcasts/Loose.mp3", PathGuard.Operation.write),
        ("Podcasts/Show/Sub/Episode.mp3", .write),
        ("Podcasts/Show/Sub", .createDirectory),
        ("Podcasts/Show/cover.jpg", .write),
        ("Podcasts/Show/video.m4v", .write),
        ("Podcasts/Show/.hidden.mp3", .write),
        ("Podcasts", .delete),
        ("Podcasts/Show/Episode.mp3", .deleteConfirmedByUser),
    ])
    func refused(path: String, operation: PathGuard.Operation) throws {
        let card = try TestCard(); defer { card.cleanUp() }
        #expect(throws: PathGuard.Violation.self) { try card.pathGuard.check(path, for: operation) }
    }

    @Test("A loose file directly in Podcasts or Audiobooks can't be deleted; an empty show folder can")
    func looseFiles() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try write(card, "Podcasts/ep.mp3", bytes: 1)
        try write(card, "Audiobooks/Loose.m4b", bytes: 1)
        try FileManager.default.createDirectory(at: card.root.appending(path: "Podcasts/Empty Show"),
                                                withIntermediateDirectories: true)
        #expect(throws: PathGuard.Violation.self) { try card.pathGuard.check("Podcasts/ep.mp3", for: .delete) }
        #expect(throws: PathGuard.Violation.self) { try card.pathGuard.check("Audiobooks/Loose.m4b", for: .delete) }
        _ = try card.pathGuard.check("Podcasts/Empty Show", for: .delete)
    }

    @Test("Stock firmware: Podcasts stays off limits")
    func stock() throws {
        let root = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let g = try PathGuard(cardRoot: root, expectedVolumeUUID: TestCard.uuid, profile: .stock,
                              homeMusicFolder: fakeHomeMusic,
                              volumeInfo: { _ in makeVolume(uuid: TestCard.uuid) })
        #expect(throws: PathGuard.Violation.self) { try g.check("Podcasts/Show/E.mp3", for: .write) }
    }

    @Test("Scanning the card leaves Podcasts out of music")
    func cardScan() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try write(card, "Podcasts/Show/E.mp3", bytes: 4)
        #expect(CardScanner.scan(folder: "", on: card.fileSystem).isEmpty)
        let listing = CardFolderListing.scan(folderName: "Podcasts", on: card.fileSystem)
        #expect(listing.files[CardLayout.caseKey("Podcasts/Show/E.mp3")]?.size == 4)
    }
}

// MARK: - Planning

@Suite("Podcasts on the card: planning")
struct PodcastPlannerTests {

    @Test("Episodes are copied as Podcasts/<Show>/<date> - <title>.<ext>")
    func copies() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let p = plan([show([episode("1", title: "The Election"), episode("2", title: "No date", published: nil, ext: "m4a")])],
                     card: card)
        #expect(Set(p.copies.map(\.destination)) == ["Podcasts/The Daily/2024-10-07 - The Election.mp3",
                                                     "Podcasts/The Daily/No date.m4a"])
        #expect(p.copies.allSatisfy { $0.kind == .add })
        #expect(p.bytesToCopy == 20 && p.episodesToAdd == 2)
    }

    @Test("Video and protected episodes are skipped, not copied")
    func skipped() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let p = plan([show([episode("1"), episode("2", ext: "m4v", kind: .video), episode("3", title: "B", protected: true)])],
                     card: card)
        #expect(p.copies.map(\.episodeID) == ["1"])
        #expect(Set(p.skipped.map(\.id)) == ["2", "3"])
    }

    @Test("A file already at the episode's name (q2-podcasts) isn't copied or recorded")
    func alreadyOnCard() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try write(card, "Podcasts/The Daily/2024-10-07 - The Election.mp3", bytes: 99)
        let p = plan([show([episode("1", title: "The Election")])], card: card)
        #expect(p.copies.isEmpty && p.alreadyOnCard == 1 && p.removals.isEmpty)
    }

    @Test("Two episodes with the same date and title get (2)")
    func sameName() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let p = plan([show([episode("a", title: "Rerun"), episode("b", title: "Rerun")])], card: card)
        let names = Dictionary(uniqueKeysWithValues: p.copies.map { ($0.episodeID, $0.destination) })
        #expect(names == ["a": "Podcasts/The Daily/2024-10-07 - Rerun.mp3",
                          "b": "Podcasts/The Daily/2024-10-07 - Rerun (2).mp3"])
    }

    @Test("Recorded episodes on the card unchanged are left; changed ones are updated in place")
    func existing() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try write(card, "Podcasts/The Daily/old name.mp3", bytes: 10)
        try write(card, "Podcasts/The Daily/two.mp3", bytes: 10)
        var manifest = SyncManifest()
        manifest.podcasts = ["1": record("Podcasts/The Daily/old name.mp3"),
                             "2": record("Podcasts/The Daily/two.mp3")]
        let p = plan([show([episode("1", title: "Renamed"), episode("2", title: "Two", size: 12)])],
                     card: card, manifest: manifest)
        #expect(p.unchangedEpisodes == 1)
        #expect(p.copies.map(\.destination) == ["Podcasts/The Daily/two.mp3"])
        #expect(p.copies.first?.kind == .update)
    }

    @Test("A new episode of a recorded show goes in that show's folder")
    func recordedFolder() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try write(card, "Podcasts/Daily Show/one.mp3", bytes: 10)
        var manifest = SyncManifest()
        manifest.podcasts = ["1": record("Podcasts/Daily Show/one.mp3")]
        let p = plan([show([episode("1"), episode("2", title: "New")])], card: card, manifest: manifest)
        #expect(p.copies.map(\.destination) == ["Podcasts/Daily Show/2024-10-07 - New.mp3"])
    }

    @Test("Two shows with the same title get separate folders")
    func sameShowTitle() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try write(card, "Podcasts/The Daily/one.mp3", bytes: 10)
        var manifest = SyncManifest()
        manifest.podcasts = ["1": record("Podcasts/The Daily/one.mp3", show: "show-a")]
        let p = plan([show([episode("1")]), show([episode("2", show: "show-b", title: "Other")])],
                     card: card, manifest: manifest)
        #expect(p.copies.map(\.destination) == ["Podcasts/The Daily (2)/2024-10-07 - Other.mp3"])
    }

    @Test("Removals: no longer downloaded, played with Unplayed only, show unticked, podcasts off")
    func removals() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        for name in ["gone", "played", "other", "kept"] { try write(card, "Podcasts/The Daily/\(name).mp3", bytes: 10) }
        var manifest = SyncManifest()
        manifest.podcasts = ["gone": record("Podcasts/The Daily/gone.mp3"),
                             "played": record("Podcasts/The Daily/played.mp3"),
                             "other": record("Podcasts/The Daily/other.mp3", show: "show-b"),
                             "kept": record("Podcasts/The Daily/kept.mp3"),
                             "missing": record("Podcasts/The Daily/missing.mp3")]
        let shows = [show([episode("played", state: .played), episode("kept", state: .inProgress)]),
                     show([episode("other", show: "show-b")])]
        let selection = PodcastSelection(isEnabled: true, includesAll: false, showIDs: ["show-a"], unplayedOnly: true)
        let p = plan(shows, selection, card: card, manifest: manifest)
        let reasons = Dictionary(uniqueKeysWithValues: p.removals.map { ($0.episodeID, $0.reason) })
        #expect(reasons == ["gone": .notDownloaded, "played": .played, "other": .showNotChosen])
        #expect(p.forgotten == ["missing"])
        #expect(p.unchangedEpisodes == 1)
        #expect(p.bytesFreedByRemovals == 30)

        let off = plan(shows, PodcastSelection(), card: card, manifest: manifest)
        #expect(off.removals.count == 4 && off.removals.allSatisfy { $0.reason == .podcastsOff })
    }

    @Test("A recorded episode that's now protected stays on the card")
    func keepSkipped() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try write(card, "Podcasts/The Daily/one.mp3", bytes: 10)
        var manifest = SyncManifest()
        manifest.podcasts = ["1": record("Podcasts/The Daily/one.mp3")]
        let p = plan([show([episode("1", protected: true)])], card: card, manifest: manifest)
        #expect(p.isEmpty)
    }

    @Test("Files Q2 Sync didn't copy are never removed")
    func othersFilesStay() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try write(card, "Podcasts/The Daily/from q2-podcasts.mp3", bytes: 10)
        let p = plan([], PodcastSelection(), card: card)
        #expect(p.isEmpty)
    }

    @Test("The date in the name follows the time zone")
    func timeZone() {
        let late = episode("1", title: "Late", published: oct7 + 13 * 3600) // 2024-10-08 01:00 UTC
        #expect(PodcastPlanner.fileName(for: late, timeZone: utc) == "2024-10-08 - Late.mp3")
        let pacific = TimeZone(identifier: "America/Los_Angeles")!
        #expect(PodcastPlanner.fileName(for: late, timeZone: pacific) == "2024-10-07 - Late.mp3")
    }

    @Test("Manifests without podcasts still load")
    func manifestDecoding() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(SyncManifest.self, from: Data(#"{"formatVersion":1,"entries":{},"playlistFiles":{}}"#.utf8))
        #expect(manifest.podcasts == nil)
    }
}
