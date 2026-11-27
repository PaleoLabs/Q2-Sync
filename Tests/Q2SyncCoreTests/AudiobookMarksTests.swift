//
//  AudiobookMarksTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Tests for the Books browser's marks (on Q2 / next sync / not chosen /
//  can't sync), the book IDs in the Mac-side card record they come from,
//  and when the sidebar's Audiobooks section shows (#70).
//
//  SAFETY
//  In-memory values and temp folders only.
//

import Foundation
import Testing
@testable import Q2SyncCore

@Suite("Audiobook marks")
struct AudiobookMarksTests {

    func book(_ id: String, _ availability: TrackAvailability = .available) -> Audiobook {
        Audiobook(id: id, title: id, author: nil, durationSeconds: 60,
                  parts: [AudiobookPart(fileURL: URL(filePath: "/\(id).m4b"), trackNumber: 0, discNumber: 0,
                                        durationSeconds: 60, fileSize: 10)],
                  availability: availability)
    }

    /// A card record with these books on it.
    func record(_ ids: [String]) -> CardContentsRecord {
        var manifest = SyncManifest()
        manifest.audiobooks = Dictionary(uniqueKeysWithValues: ids.map {
            ($0, AudiobookRecord(folder: "Audiobooks/\($0)", title: $0, files: []))
        })
        return CardContentsRecord(volumeUUID: "ABCD-1234", manifest: manifest)
    }

    func device(_ uuid: String, audiobooks: Bool?) -> KnownDevice {
        var device = KnownDevice(volumeUUID: uuid, name: "Q2", firmware: .q2Pod, bookmarkData: Data(),
                                 addedDate: .now, hasCompletedFirstSync: false)
        device.audiobooks = audiobooks.map { AudiobookSelection(isEnabled: $0) }
        return device
    }

    @Test("The card record keeps the books' ids")
    func recordKeepsBookIDs() {
        #expect(record(["a", "b"]).audiobookIDs == ["a", "b"])
        // A manifest from before audiobooks: known to have none.
        #expect(CardContentsRecord(volumeUUID: "ABCD", manifest: SyncManifest()).audiobookIDs == [])
    }

    @Test("A record saved before audiobooks were recorded still loads, with no books known")
    func oldRecordLoads() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = #"{"checkedAt":"2026-11-20T10:00:00Z","trackIDs":["A1"],"volumeUUID":"ABCD"}"#
        try Data(old.utf8).write(to: folder.appending(path: "ABCD.json"))

        let loaded = try #require(CardContentsStore(directory: folder).load(volumeUUID: "ABCD"))
        #expect(loaded.trackIDs == ["A1"])
        #expect(loaded.audiobookIDs == nil)
        #expect(!AudiobookMarks(record: loaded, selection: AudiobookSelection(isEnabled: true)).hasQ2)
    }

    @Test("Without a Q2, only books that can't be copied are marked")
    func noQ2() {
        let marks = AudiobookMarks(record: nil, selection: nil)
        #expect(!marks.hasQ2)
        #expect(marks.placement(of: book("a")) == nil)
        #expect(marks.placement(of: book("p", .drmProtected)) == .cantSync)
    }

    @Test("On Q2, next sync and not chosen follow the record and the Q2's settings")
    func placements() {
        let selection = AudiobookSelection(isEnabled: true, includesAll: false, bookIDs: ["on", "next"])
        let marks = AudiobookMarks(record: record(["on", "old"]), selection: selection)
        #expect(marks.hasQ2)
        #expect(marks.placement(of: book("on")) == .onQ2)
        #expect(marks.placement(of: book("next")) == .nextSync)
        #expect(marks.placement(of: book("other")) == .notChosen)
        // On the card but no longer downloaded: the card still has it.
        #expect(marks.placement(of: book("old", .cloudOnly)) == .onQ2)
        #expect(marks.placement(of: book("cloud", .cloudOnly)) == .cantSync)
    }

    @Test("With audiobooks off, nothing is copied at the next sync")
    func audiobooksOff() {
        let marks = AudiobookMarks(record: record([]), selection: AudiobookSelection(isEnabled: false))
        #expect(marks.placement(of: book("a")) == .notChosen)
    }

    @Test("The Audiobooks section shows when any known Q2 syncs audiobooks")
    func sectionShowsForAnyQ2() {
        #expect(![KnownDevice]().anySyncsAudiobooks)
        #expect(![device("A", audiobooks: nil), device("B", audiobooks: false)].anySyncsAudiobooks)
        #expect([device("A", audiobooks: false), device("B", audiobooks: true)].anySyncsAudiobooks)
    }
}
