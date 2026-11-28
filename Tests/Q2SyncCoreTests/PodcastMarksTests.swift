//
//  PodcastMarksTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Tests for the Episodes browser's marks (on Q2 / next sync / not chosen
//  / can't sync), the episode IDs in the Mac-side card record they come
//  from, and when the sidebar's Podcasts section shows (#70).
//
//  SAFETY
//  In-memory values and temp folders only.
//

import Foundation
import Testing
@testable import Q2SyncCore

@Suite("Podcast marks")
struct PodcastMarksTests {

    func episode(_ id: String, show: String = "show-a", kind: PodcastEpisodeKind = .audio,
                 state: PodcastPlayState = .unplayed, protected: Bool = false) -> PodcastEpisode {
        PodcastEpisode(id: id, showID: show, showTitle: "Show", title: id, published: nil,
                       fileURL: URL(filePath: "/\(id).mp3"), fileSize: 10, kind: kind,
                       playState: state, isProtected: protected)
    }

    /// A card record with these episodes on it.
    func record(_ ids: [String]) -> CardContentsRecord {
        var manifest = SyncManifest()
        manifest.podcasts = Dictionary(uniqueKeysWithValues: ids.map {
            ($0, PodcastEpisodeRecord(path: "Podcasts/Show/\($0).mp3", showID: "show-a", showTitle: "Show",
                                      title: $0, sourceSize: 10, cardSize: 10, syncedAt: .now))
        })
        return CardContentsRecord(volumeUUID: "ABCD-1234", manifest: manifest)
    }

    func device(_ uuid: String, podcasts: Bool?) -> KnownDevice {
        var device = KnownDevice(volumeUUID: uuid, name: "Q2", firmware: .q2Pod, bookmarkData: Data(),
                                 addedDate: .now, hasCompletedFirstSync: false)
        device.podcasts = podcasts.map { PodcastSelection(isEnabled: $0) }
        return device
    }

    @Test("The card record keeps the episodes' ids")
    func recordKeepsEpisodeIDs() {
        #expect(record(["a", "b"]).podcastEpisodeIDs == ["a", "b"])
        // A manifest from before podcasts: known to have none.
        #expect(CardContentsRecord(volumeUUID: "ABCD", manifest: SyncManifest()).podcastEpisodeIDs == [])
    }

    @Test("A record saved before podcasts were recorded still loads, with no episodes known")
    func oldRecordLoads() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = #"{"audiobookIDs":[],"checkedAt":"2026-11-20T10:00:00Z","trackIDs":["A1"],"volumeUUID":"ABCD"}"#
        try Data(old.utf8).write(to: folder.appending(path: "ABCD.json"))

        let loaded = try #require(CardContentsStore(directory: folder).load(volumeUUID: "ABCD"))
        #expect(loaded.audiobookIDs == [])
        #expect(loaded.podcastEpisodeIDs == nil)
        #expect(!PodcastMarks(record: loaded, selection: PodcastSelection(isEnabled: true)).hasQ2)
    }

    @Test("Without a Q2, only episodes that can't be copied are marked")
    func noQ2() {
        let marks = PodcastMarks(record: nil, selection: nil)
        #expect(!marks.hasQ2)
        #expect(marks.placement(of: episode("a")) == nil)
        #expect(marks.placement(of: episode("v", kind: .video)) == .cantSync)
        #expect(marks.placement(of: episode("p", protected: true)) == .cantSync)
    }

    @Test("On Q2, next sync and not chosen follow the record and the Q2's settings")
    func placements() {
        let selection = PodcastSelection(isEnabled: true, includesAll: false, showIDs: ["show-a"],
                                         unplayedOnly: true)
        let marks = PodcastMarks(record: record(["on"]), selection: selection)
        #expect(marks.hasQ2)
        #expect(marks.placement(of: episode("on")) == .onQ2)
        #expect(marks.placement(of: episode("next")) == .nextSync)
        #expect(marks.placement(of: episode("inProgress", state: .inProgress)) == .nextSync)
        #expect(marks.placement(of: episode("played", state: .played)) == .notChosen)
        #expect(marks.placement(of: episode("other", show: "show-b")) == .notChosen)
        #expect(marks.placement(of: episode("video", kind: .video)) == .cantSync)
    }

    @Test("With podcasts off, nothing is copied at the next sync")
    func podcastsOff() {
        let marks = PodcastMarks(record: record([]), selection: PodcastSelection(isEnabled: false))
        #expect(marks.placement(of: episode("a")) == .notChosen)
    }

    @Test("The Podcasts section shows when any known Q2 syncs podcasts")
    func sectionShowsForAnyQ2() {
        #expect(![KnownDevice]().anySyncsPodcasts)
        #expect(![device("A", podcasts: nil), device("B", podcasts: false)].anySyncsPodcasts)
        #expect([device("A", podcasts: false), device("B", podcasts: true)].anySyncsPodcasts)
    }
}
