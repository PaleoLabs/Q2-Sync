//
//  PlaylistTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Tests for playlist file names, limits, ownership, M3U output, the
//  playlist-folder guard rule, and writing playlists during a sync.
//
//  SAFETY
//  In-memory data and temp folders only.
//

import Foundation
import Testing
@testable import Q2SyncCore

/// A playlist for tests.
func makePlaylist(_ id: String, _ name: String, _ trackIDs: [String] = [], kind: PlaylistKind = .regular) -> Playlist {
    Playlist(id: id, name: name, kind: kind, parentID: nil, trackIDs: trackIDs)
}

/// Card files in the playlist folder, keyed the way the planner expects.
func folderFiles(_ names: [String]) -> [String: CardFile] {
    Dictionary(names.map { name -> (String, CardFile) in
        let path = "_explaylist_data/\(name)"
        return (CardLayout.caseKey(path), CardFile(path: path, size: 10))
    }, uniquingKeysWith: { a, _ in a })
}

@Suite("Playlist planning")
struct PlaylistPlanTests {

    let profile = DeviceProfile.q2Pod

    @Test("Playlists are written as cleaned names in _explaylist_data")
    func names() {
        let plan = PlaylistWriter.plan(playlists: [makePlaylist("1", "Road Trip"), makePlaylist("2", "AC/DC: Best?")],
                                       manifest: SyncManifest(), folderFiles: [:], profile: profile)
        #expect(Set(plan.writes.map(\.path)) == ["_explaylist_data/Road Trip.m3u", "_explaylist_data/AC_DC_ Best_.m3u"])
        #expect(plan.writes.first { $0.id == "2" }?.nameWasChanged == true)
        #expect(plan.writes.first { $0.id == "1" }?.nameWasChanged == false)
    }

    @Test("Names are limited to 63 bytes, including numbered variants")
    func nameLimit() {
        let long = String(repeating: "é", count: 40) // 80 bytes
        let plan = PlaylistWriter.plan(playlists: [makePlaylist("1", long), makePlaylist("2", long)],
                                       manifest: SyncManifest(), folderFiles: [:], profile: profile)
        for write in plan.writes {
            #expect(write.nameOnDevice.utf8.count <= 63)
        }
        #expect(Set(plan.writes.map(\.path)).count == 2)
    }

    @Test("A user's own playlist file is never overwritten")
    func userFileKept() {
        let plan = PlaylistWriter.plan(playlists: [makePlaylist("1", "Mix")], manifest: SyncManifest(),
                                       folderFiles: folderFiles(["mix.M3U", "Mix.jpg"]), profile: profile)
        #expect(plan.writes.map(\.path) == ["_explaylist_data/Mix (2).m3u"])
        #expect(plan.removals.isEmpty)
        #expect(plan.otherPlaylistFiles == 1)
    }

    @Test("Only 100 playlists are written; the rest are listed")
    func limit() {
        let playlists = (1...105).map { makePlaylist("\($0)", String(format: "List %03d", $0)) }
        let plan = PlaylistWriter.plan(playlists: playlists, manifest: SyncManifest(), folderFiles: [:], profile: profile)
        #expect(plan.writes.count == 100)
        #expect(plan.overLimit.map(\.name) == ["List 101", "List 102", "List 103", "List 104", "List 105"])
    }

    @Test("Our file for a deselected playlist is removed; others' files never are")
    func removals() {
        var manifest = SyncManifest()
        manifest.playlistFiles["old"] = "_explaylist_data/Old.m3u"
        let plan = PlaylistWriter.plan(playlists: [], manifest: manifest,
                                       folderFiles: folderFiles(["Old.m3u", "Mine.m3u"]), profile: profile)
        #expect(plan.removals.map(\.path) == ["_explaylist_data/Old.m3u"])
    }

    @Test("A renamed playlist writes the new name and removes our old file")
    func rename() {
        var manifest = SyncManifest()
        manifest.playlistFiles["1"] = "_explaylist_data/Old Name.m3u"
        let plan = PlaylistWriter.plan(playlists: [makePlaylist("1", "New Name")], manifest: manifest,
                                       folderFiles: folderFiles(["Old Name.m3u"]), profile: profile)
        #expect(plan.writes.map(\.path) == ["_explaylist_data/New Name.m3u"])
        #expect(plan.removals.map(\.path) == ["_explaylist_data/Old Name.m3u"])
    }

    @Test("A numbered name stays stable on later syncs")
    func stable() {
        var manifest = SyncManifest()
        manifest.playlistFiles["1"] = "_explaylist_data/Mix (2).m3u"
        let plan = PlaylistWriter.plan(playlists: [makePlaylist("1", "Mix")], manifest: manifest,
                                       folderFiles: folderFiles(["Mix.m3u", "Mix (2).m3u"]), profile: profile)
        #expect(plan.writes.map(\.path) == ["_explaylist_data/Mix (2).m3u"])
        #expect(plan.removals.isEmpty)
    }
}

@Suite("Playlist rendering")
struct PlaylistRenderTests {

    let profile = DeviceProfile.q2Pod

    func entry(_ path: String, title: String = "T", artist: String? = "A") -> SyncManifest.Entry {
        SyncManifest.Entry(path: path, sourceSize: 1, sourceModified: nil, cardSize: 1, syncedAt: .now,
                           title: title, artist: artist, album: nil)
    }

    @Test("M3U output: header, EXTINF, device paths, CRLF, order and duplicates kept")
    func output() {
        let entries = ["a": entry("Music/A/B/01 One.m4a", title: "One"),
                       "b": entry("Music/A/B/02 Two.m4a", title: "Two")]
        var track = makeCopyableTrack(id: "a", title: "One", artist: "A")
        track = Track(id: track.id, title: track.title, artist: "A", albumArtist: "A", album: "B", genre: nil,
                      trackNumber: 1, discNumber: 1, discCount: 1, isCompilation: false, durationSeconds: 356.6,
                      fileSize: 1, fileURL: nil, fileKind: nil, modifiedDate: nil, availability: .available)
        let rendered = PlaylistWriter.render(makePlaylist("p", "Mix", ["b", "a", "cloud", "b"]),
                                             entries: entries, tracks: ["a": track], profile: profile)
        let text = String(decoding: rendered.data, as: UTF8.self)
        #expect(text == "#EXTM3U\r\n"
            + "#EXTINF:0,A - Two\r\n/mnt/mmc/Music/A/B/02 Two.m4a\r\n"
            + "#EXTINF:357,A - One\r\n/mnt/mmc/Music/A/B/01 One.m4a\r\n"
            + "#EXTINF:0,A - Two\r\n/mnt/mmc/Music/A/B/02 Two.m4a\r\n")
        #expect(rendered.songCount == 3)
        #expect(rendered.missingCount == 1)
        #expect(!rendered.data.starts(with: [0xEF, 0xBB, 0xBF]), "No byte-order mark")
    }

    @Test("Every comment line contains #EXT, and titles can't break lines")
    func commentLines() {
        let entries = ["a": entry("Music/x.mp3", title: "Line\nBreak #hash")]
        let rendered = PlaylistWriter.render(makePlaylist("p", "P", ["a"]), entries: entries, tracks: [:], profile: profile)
        let lines = String(decoding: rendered.data, as: UTF8.self).components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines.count == 3)
        for line in lines where line.hasPrefix("#") { #expect(line.contains("#EXT")) }
    }

    @Test("Non-ASCII names are written as NFC UTF-8")
    func unicode() {
        let entries = ["a": entry("Music/Beyonce\u{0301}/x.mp3")]
        let rendered = PlaylistWriter.render(makePlaylist("p", "P", ["a"]), entries: entries, tracks: [:], profile: profile)
        #expect(String(decoding: rendered.data, as: UTF8.self).contains("/mnt/mmc/Music/Beyonc\u{00E9}/x.mp3"))
    }

    @Test("Windows-drive path style")
    func windowsStyle() {
        #expect(PlaylistWriter.devicePath(for: "Music/A/01 X.mp3", style: .windowsDrive(letter: "A"))
                == #"A:\Music\A\01 X.mp3"#)
    }
}

@Suite("Playlist folder guard and sync")
struct PlaylistSyncTests {

    @Test("Only .m3u files directly in the playlist folder may be written or deleted")
    func guardRule() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        _ = try card.pathGuard.check("_explaylist_data/Mix.m3u", for: .write)
        _ = try card.pathGuard.check("_explaylist_data/Mix.M3U", for: .delete)
        _ = try card.pathGuard.check("_explaylist_data", for: .createDirectory)
        #expect(throws: PathGuard.Violation.self) { try card.pathGuard.check("_explaylist_data/Mix.jpg", for: .delete) }
        #expect(throws: PathGuard.Violation.self) { try card.pathGuard.check("_explaylist_data/sub/x.m3u", for: .write) }
        #expect(throws: PathGuard.Violation.self) { try card.pathGuard.check("_explaylist_data", for: .delete) }
    }

    @Test("A sync writes playlists of the songs on the card, then reports them unchanged")
    func endToEnd() async throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let mac = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: mac) }
        let logs = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: logs) }
        let source = mac.appending(path: "a.mp3")
        try Data(count: 100).write(to: source)
        let track = makeCopyableTrack(id: "A", title: "Alpha", size: 100, fileURL: source)
        let cloud = makeCopyableTrack(id: "C", title: "Cloud", availability: .cloudOnly)
        let selection = ResolvedSelection(tracksToSync: [track], skippedTracks: [cloud],
                                          playlists: [makePlaylist("P", "Mix", ["A", "C"])], missingSelectionCount: 0)

        func makePlan() throws -> (SyncPlan, SyncManifest) {
            let manifest = try SyncManifest.load(from: card.fileSystem)
            var plan = SyncPlanner.plan(selection: selection, allSelectedIDs: ["A", "C"], manifest: manifest,
                                        cardFiles: CardScanner.scan(folder: "Music", on: card.fileSystem),
                                        playlistFolderFiles: CardScanner.scan(folder: "_explaylist_data", on: card.fileSystem),
                                        layout: CardLayout(profile: .q2Pod))
            PlaylistWriter.dropUnchangedWrites(in: &plan, manifest: manifest, profile: .q2Pod) {
                try? Data(contentsOf: card.fileSystem.urlForReading($0))
            }
            return (plan, manifest)
        }

        let executor = SyncExecutor(fileSystem: card.fileSystem, deviceName: "Test", logsDirectory: logs)
        let (plan, manifest) = try makePlan()
        let report = await executor.run(plan: plan, manifest: manifest, options: SyncOptions()) { _ in }
        #expect(report.succeeded)
        #expect(report.playlistsWritten == 1)
        #expect(report.playlistSongsMissing == 1)

        let text = try String(contentsOf: card.root.appending(path: "_explaylist_data/Mix.m3u"), encoding: .utf8)
        #expect(text.contains("/mnt/mmc/Music/Artist/Album/01 Alpha.mp3"))
        #expect(!text.contains("Cloud"))
        #expect(try SyncManifest.load(from: card.fileSystem).playlistFiles["P"] == "_explaylist_data/Mix.m3u")

        // Nothing changed: the second plan is empty ("Already Up to Date").
        let (second, _) = try makePlan()
        #expect(second.isEmpty)
    }
}

@Suite("Playlist names on the card")
struct PlaylistNamingTests {

    func playlist(_ id: String, _ name: String, kind: PlaylistKind = .regular, in parent: String? = nil) -> Playlist {
        Playlist(id: id, name: name, kind: kind, parentID: parent, trackIDs: [])
    }

    @Test("Same-named playlists in a folder are named after it")
    func folderPrefix() {
        let folders = [playlist("F", "Decades", kind: .folder)]
        let named = PlaylistNaming.disambiguate([
            playlist("A", "1980's Music", kind: .smart, in: "F"),
            playlist("B", "1980's Music"),
            playlist("C", "Workout", in: "F"),          // unique: unchanged
            playlist("D", "100 Most Played", kind: .smart),
            playlist("E", "100 Most Played"),           // both top level: unchanged
        ], folders: folders)
        #expect(named.map(\.name) == ["Decades - 1980's Music", "1980's Music", "Workout",
                                      "100 Most Played", "100 Most Played"])
    }

    @Test("A renamed playlist's old (2) file is replaced by the new name")
    func replacesOldFile() {
        var manifest = SyncManifest()
        manifest.playlistFiles = ["A": "_explaylist_data/1980's Music (2).m3u", "B": "_explaylist_data/1980's Music.m3u"]
        let files = Dictionary(manifest.playlistFiles.values.map { (CardLayout.caseKey($0), CardFile(path: $0, size: 100)) },
                               uniquingKeysWith: { a, _ in a })
        let playlists = PlaylistNaming.disambiguate(
            [playlist("A", "1980's Music", kind: .smart, in: "F"), playlist("B", "1980's Music")],
            folders: [playlist("F", "Decades", kind: .folder)])
        let plan = PlaylistWriter.plan(playlists: playlists, manifest: manifest, folderFiles: files, profile: .q2Pod)
        #expect(Set(plan.writes.map(\.path)) == ["_explaylist_data/Decades - 1980's Music.m3u",
                                                  "_explaylist_data/1980's Music.m3u"])
        #expect(plan.removals.map(\.path) == ["_explaylist_data/1980's Music (2).m3u"])
    }
}

@Suite("Only changed playlists up for import")
struct PlaylistImportTests {

    /// A card with two songs synced, and a helper that syncs playlists.
    struct Fixture {
        let card: TestCard
        let mac: URL
        let logs: URL
        let tracks: [Track]

        func cleanUp() {
            card.cleanUp()
            try? FileManager.default.removeItem(at: mac)
            try? FileManager.default.removeItem(at: logs)
        }

        func sync(_ playlists: [Playlist], onlyChanged: Bool = true, reimportAll: Bool = false) async throws
            -> (SyncPlan, SyncReport) {
            let manifest = try SyncManifest.load(from: card.fileSystem)
            let selection = ResolvedSelection(tracksToSync: tracks, skippedTracks: [], playlists: playlists,
                                              missingSelectionCount: 0)
            var plan = SyncPlanner.plan(selection: selection, allSelectedIDs: Set(tracks.map(\.id)), manifest: manifest,
                                        cardFiles: CardScanner.scan(folder: "Music", on: card.fileSystem),
                                        playlistFolderFiles: CardScanner.scan(folder: "_explaylist_data", on: card.fileSystem),
                                        layout: CardLayout(profile: .q2Pod))
            plan.playlistPlan.onlyChangedForImport = onlyChanged
            plan.playlistPlan.reimportAll = reimportAll
            PlaylistWriter.dropUnchangedWrites(in: &plan, manifest: manifest, profile: .q2Pod) { path in
                try? Data(contentsOf: card.fileSystem.urlForReading(path))
            }
            let report = await SyncExecutor(fileSystem: card.fileSystem, deviceName: "T", logsDirectory: logs)
                .run(plan: plan, manifest: manifest, options: SyncOptions()) { _ in }
            return (plan, report)
        }

        func inImportFolder() -> Set<String> {
            let folder = card.root.appending(path: "_explaylist_data")
            return Set(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".m3u") })
        }
    }

    func makeFixture() throws -> Fixture {
        let card = try TestCard(), mac = try makeTempFolder(), logs = try makeTempFolder()
        var tracks: [Track] = []
        for (index, id) in ["A", "B"].enumerated() {
            let url = mac.appending(path: "\(id).mp3")
            try Data(repeating: UInt8(index + 1), count: 1_000 + index).write(to: url)
            tracks.append(makeCopyableTrack(id: id, title: "Song \(id)", number: index + 1,
                                            size: UInt64(1_000 + index), fileURL: url))
        }
        return Fixture(card: card, mac: mac, logs: logs, tracks: tracks)
    }

    func playlist(_ id: String, _ name: String, _ songs: [PersistentID]) -> Playlist {
        Playlist(id: id, name: name, kind: .regular, parentID: nil, trackIDs: songs)
    }

    @Test("Only new or changed playlists stay in the import folder")
    func cycle() async throws {
        let f = try makeFixture(); defer { f.cleanUp() }
        let one = playlist("P1", "One", ["A"]), two = playlist("P2", "Two", ["B"])

        // First sync: both are new, both up for import.
        var (plan, report) = try await f.sync([one, two])
        #expect(report.succeeded && report.playlistsToImport == 2)
        #expect(f.inImportFolder() == ["One.m3u", "Two.m3u"])

        // Next sync, nothing changed: both were imported, so they're taken out.
        (plan, report) = try await f.sync([one, two])
        #expect(plan.playlistPlan.leavingImport.count == 2 && plan.playlistPlan.writes.isEmpty)
        #expect(report.playlistsTakenOut == 2 && report.playlistsToImport == 0)
        #expect(f.inImportFolder().isEmpty)

        // And then there's nothing to do.
        (plan, _) = try await f.sync([one, two])
        #expect(plan.isEmpty)

        // One playlist changes: only it goes up.
        let changed = playlist("P1", "One", ["A", "B"])
        (plan, report) = try await f.sync([changed, two])
        #expect(plan.playlistPlan.writes.map(\.playlist.id) == ["P1"])
        #expect(report.playlistsToImport == 1 && f.inImportFolder() == ["One.m3u"])

        // A full re-import puts everything up.
        (_, report) = try await f.sync([changed, two], reimportAll: true)
        #expect(f.inImportFolder() == ["One.m3u", "Two.m3u"] && report.playlistsToImport == 2)

        // Turned off: every playlist is kept in the folder.
        (_, _) = try await f.sync([changed, two])
        #expect(f.inImportFolder().isEmpty)
        (_, report) = try await f.sync([changed, two], onlyChanged: false)
        #expect(f.inImportFolder() == ["One.m3u", "Two.m3u"])
    }

    @Test("Upgrading: identical files already on the card count as imported")
    func upgrade() async throws {
        let f = try makeFixture(); defer { f.cleanUp() }
        let one = playlist("P1", "One", ["A"])
        // A sync from before this existed: files written, no fingerprints.
        _ = try await f.sync([one], onlyChanged: false)
        var manifest = try SyncManifest.load(from: f.card.fileSystem)
        manifest.playlistDigests = nil
        try manifest.save(to: f.card.fileSystem)

        let (plan, report) = try await f.sync([one])
        #expect(plan.playlistPlan.leavingImport.count == 1)
        #expect(report.playlistsTakenOut == 1 && f.inImportFolder().isEmpty)
    }

    @Test("The rule itself")
    func rule() {
        let data = Data("#EXTM3U\r\n".utf8)
        let digest = PlaylistImportRule.digest(data)
        #expect(!PlaylistImportRule.needsImport(data, previousDigest: digest, fileOnCard: nil, reimportAll: false))
        #expect(PlaylistImportRule.needsImport(data, previousDigest: "other", fileOnCard: data, reimportAll: false))
        #expect(PlaylistImportRule.needsImport(data, previousDigest: digest, fileOnCard: nil, reimportAll: true))
        #expect(!PlaylistImportRule.needsImport(data, previousDigest: nil, fileOnCard: data, reimportAll: false))
        #expect(PlaylistImportRule.needsImport(data, previousDigest: nil, fileOnCard: nil, reimportAll: false))
    }
}
