//
//  CardToolsTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Tests for "Verify Card" (finding damaged, wrong-size and missing songs,
//  skipping changed ones, and repairing) and for backing up and restoring
//  Q2 Pod's data, including the path guard's narrow restore exception.
//  Cards, Macs and backup folders are temp folders.
//

import Foundation
import Testing
@testable import Q2SyncCore

@Suite("Verify card")
struct CardVerifierTests {

    /// A card with songs synced from a fake Mac.
    struct Setup {
        let card: TestCard
        let mac: URL
        let logs: URL
        let tracks: [Track]
        var byID: [PersistentID: Track] { Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) }) }
        func path(_ id: String) throws -> URL {
            card.root.appending(path: try SyncManifest.load(from: card.fileSystem).entries[id]!.path)
        }
        func cleanUp() {
            card.cleanUp()
            try? FileManager.default.removeItem(at: mac)
            try? FileManager.default.removeItem(at: logs)
        }
    }

    func makeSetup() async throws -> Setup {
        let card = try TestCard()
        let mac = try makeTempFolder(), logs = try makeTempFolder()
        var tracks: [Track] = []
        for (index, id) in ["A", "B", "C"].enumerated() {
            let url = mac.appending(path: "\(id).mp3")
            try Data((0..<(2_000_000 + index * 1000)).map { UInt8(($0 + index) % 251) }).write(to: url)
            let size = UInt64(2_000_000 + index * 1000)
            tracks.append(makeCopyableTrack(id: id, title: "Song \(id)", number: index + 1, size: size, fileURL: url))
        }
        let manifest = try SyncManifest.load(from: card.fileSystem)
        let plan = SyncPlanner.plan(selection: resolved(tracks), allSelectedIDs: Set(tracks.map(\.id)), manifest: manifest,
                                    cardFiles: CardScanner.scan(folder: "Music", on: card.fileSystem),
                                    layout: CardLayout(profile: .q2Pod))
        let report = await SyncExecutor(fileSystem: card.fileSystem, deviceName: "T", logsDirectory: logs)
            .run(plan: plan, manifest: manifest, options: SyncOptions()) { _ in }
        #expect(report.added == 3)
        return Setup(card: card, mac: mac, logs: logs, tracks: tracks)
    }

    @Test("A healthy card passes")
    func healthy() async throws {
        let setup = try await makeSetup(); defer { setup.cleanUp() }
        var last = VerifyProgress()
        let result = CardVerifier.verify(manifest: try SyncManifest.load(from: setup.card.fileSystem),
                                         tracks: setup.byID, fileSystem: setup.card.fileSystem) { last = $0 }
        #expect(result.verified == 3 && result.problems.isEmpty)
        #expect(last.songsDone == 3 && last.fraction == 1)
    }

    @Test("Damaged, wrong-size and missing songs are found, and repairing fixes them")
    func findsAndRepairs() async throws {
        let setup = try await makeSetup(); defer { setup.cleanUp() }
        // A: flip one byte in the middle. B: cut short. C: delete.
        let a = try setup.path("A")
        let handle = try FileHandle(forUpdating: a)
        try handle.seek(toOffset: 1_500_000)
        try handle.write(contentsOf: Data([0xAB]))
        try handle.close()
        let b = try setup.path("B")
        let shortened = try FileHandle(forWritingTo: b); try shortened.truncate(atOffset: 1000); try shortened.close()
        try FileManager.default.removeItem(at: try setup.path("C"))

        let manifest = try SyncManifest.load(from: setup.card.fileSystem)
        let result = CardVerifier.verify(manifest: manifest, tracks: setup.byID, fileSystem: setup.card.fileSystem)
        let kinds = Dictionary(uniqueKeysWithValues: result.problems.map { ($0.trackID, $0.kind) })
        #expect(kinds == ["A": .damaged, "B": .wrongSize, "C": .missing])

        // Repair through the normal executor.
        let plan = CardVerifier.repairPlan(for: result.problems, tracks: setup.byID)
        #expect(plan.copies.count == 3)
        let report = await SyncExecutor(fileSystem: setup.card.fileSystem, deviceName: "T", logsDirectory: setup.logs)
            .run(plan: plan, manifest: manifest, options: SyncOptions()) { _ in }
        #expect(report.succeeded && report.updated == 3)
        let again = CardVerifier.verify(manifest: try SyncManifest.load(from: setup.card.fileSystem),
                                        tracks: setup.byID, fileSystem: setup.card.fileSystem)
        #expect(again.verified == 3 && again.problems.isEmpty)
    }

    @Test("Songs changed on the Mac, or not on the Mac, are skipped")
    func skips() async throws {
        let setup = try await makeSetup(); defer { setup.cleanUp() }
        var tracks = setup.byID
        let a = tracks["A"]!
        tracks["A"] = makeCopyableTrack(id: "A", title: a.title, size: a.fileSize + 5, fileURL: a.fileURL!) // changed
        tracks["B"] = nil                                                                                    // gone
        let result = CardVerifier.verify(manifest: try SyncManifest.load(from: setup.card.fileSystem),
                                         tracks: tracks, fileSystem: setup.card.fileSystem)
        #expect(result.verified == 1 && result.skippedChanged == 1 && result.skippedNoMacFile == 1)
    }

    @Test("Comparing never changes either file")
    func readOnly() async throws {
        let setup = try await makeSetup(); defer { setup.cleanUp() }
        let mac = setup.tracks[0].fileURL!, card = try setup.path("A")
        let before = (try Data(contentsOf: mac), try Data(contentsOf: card))
        let datesBefore = try FileManager.default.attributesOfItem(atPath: mac.path)[.modificationDate] as? Date
        _ = CardVerifier.compare(card: card, mac: mac, expectedSize: setup.tracks[0].fileSize)
        #expect(try Data(contentsOf: mac) == before.0 && (try Data(contentsOf: card)) == before.1)
        #expect(try FileManager.default.attributesOfItem(atPath: mac.path)[.modificationDate] as? Date == datesBefore)
    }
}

@Suite("Q2 Pod data backup")
struct PodDataTests {

    /// Writes some Q2 Pod data onto a test card.
    func addPodData(to card: TestCard) throws {
        let root = card.root
        try Data("song\t5\n".utf8).write(to: root.appending(path: ".ratings.tsv"))
        try Data("#AUDIOSCROBBLER/1.1\n".utf8).write(to: root.appending(path: ".scrobbler.log"))
        try FileManager.default.createDirectory(at: root.appending(path: "EQ/Sets"), withIntermediateDirectories: true)
        try Data("Preamp: -3 dB".utf8).write(to: root.appending(path: "EQ/Bass.txt"))
        try Data("Filter 1".utf8).write(to: root.appending(path: "EQ/Sets/Mine.txt"))
        try FileManager.default.createDirectory(at: root.appending(path: "Radio"), withIntermediateDirectories: true)
        try Data("#EXTM3U\n".utf8).write(to: root.appending(path: "Radio/favourites.m3u"))
        // Not Q2 Pod data: must not be backed up.
        try Data("x".utf8).write(to: root.appending(path: "Radio/other.m3u"))
    }

    @Test("Backs up exactly Q2 Pod's data, and restores what you tick")
    func backUpAndRestore() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let backups = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: backups) }
        try addPodData(to: card)

        let info = try PodDataBackup.backUp(cardRoot: card.root, deviceName: "My Q2", volumeUUID: TestCard.uuid,
                                            to: backups, protectedFolders: [fakeHomeMusic])
        #expect(info.files.map(\.path) == [".ratings.tsv", ".scrobbler.log", "EQ/Bass.txt", "EQ/Sets/Mine.txt",
                                           "Radio/favourites.m3u"])
        let folder = try #require(info.folder)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "About this backup.txt").path))
        let read = try PodDataBackup.readBackup(at: folder)
        #expect(read.files == info.files && read.deviceName == "My Q2")
        #expect(PodDataBackup.existingBackups(in: backups).count == 1)
        #expect(Set(read.items.map(\.path)) == [".ratings.tsv", ".scrobbler.log", "EQ", "Radio/favourites.m3u"])

        // A fresh card: restore ratings and EQ only.
        let fresh = try TestCard(); defer { fresh.cleanUp() }
        let chosen = read.files.map(\.path).filter { $0 == ".ratings.tsv" || $0.hasPrefix("EQ/") }
        #expect(try fresh.fileSystem.restorePodData(from: folder, files: chosen) == 3)
        #expect(try Data(contentsOf: fresh.root.appending(path: ".ratings.tsv")) == Data("song\t5\n".utf8))
        #expect(try Data(contentsOf: fresh.root.appending(path: "EQ/Sets/Mine.txt")) == Data("Filter 1".utf8))
        #expect(!FileManager.default.fileExists(atPath: fresh.root.appending(path: ".scrobbler.log").path))
        // Restoring replaces what's there.
        try Data("newer".utf8).write(to: fresh.root.appending(path: ".ratings.tsv"))
        try fresh.fileSystem.restorePodData(from: folder, files: [".ratings.tsv"])
        #expect(try Data(contentsOf: fresh.root.appending(path: ".ratings.tsv")) == Data("song\t5\n".utf8))
    }

    @Test("An empty card has nothing to back up")
    func nothing() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let backups = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: backups) }
        #expect(throws: PodDataError.nothingToBackUp) {
            try PodDataBackup.backUp(cardRoot: card.root, deviceName: "Q2", volumeUUID: "X", to: backups,
                                     protectedFolders: [])
        }
    }

    @Test("Backups are never written into a protected folder")
    func protectedDestination() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try addPodData(to: card)
        let music = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: music) }
        #expect(throws: PodDataError.self) {
            try PodDataBackup.backUp(cardRoot: card.root, deviceName: "Q2", volumeUUID: "X",
                                     to: music.appending(path: "Backups"), protectedFolders: [music])
        }
    }

    @Test("The restore exception covers only Q2 Pod's data paths", arguments: [
        ("Music/A/B/song.mp3", false), (".ratings.tsv/x", false), ("EQ", false), ("../x", false),
        (".q2/sources.list", false), (".q2/apps/rockbox.tag", false), ("update.tar", false),
        (".ratings.tsv", true), ("EQ/Bass.txt", true), ("EQ/Sets/Mine.txt", true), (".q2/custom-sources.list", true),
        ("Radio/favourites.m3u", true), (".rockbox/config.cfg", true),
    ])
    func guardWrites(path: String, allowed: Bool) throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let approved = (try? card.pathGuard.checkPodDataPath(path, for: .write)) != nil
        #expect(approved == allowed)
    }

    @Test("Folders can be created only on the way to Q2 Pod's data")
    func guardFolders() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        for folder in ["EQ", "EQ/Sets", ".q2", "Radio", ".rockbox"] {
            #expect((try? card.pathGuard.checkPodDataPath(folder, for: .createDirectory)) != nil)
        }
        for folder in ["Music", ".q2/apps", "Podcasts", "Radio/Other"] {
            #expect((try? card.pathGuard.checkPodDataPath(folder, for: .createDirectory)) == nil)
        }
        #expect((try? card.pathGuard.checkPodDataPath(".ratings.tsv", for: .delete)) == nil)
    }

    @Test("A symlink can't redirect a restore")
    func guardSymlink() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let elsewhere = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: elsewhere) }
        try FileManager.default.createSymbolicLink(at: card.root.appending(path: "EQ"), withDestinationURL: elsewhere)
        #expect((try? card.pathGuard.checkPodDataPath("EQ/Bass.txt", for: .write)) == nil)
    }
}
