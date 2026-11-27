//
//  AudiobookSyncTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Tests for syncing audiobooks to `Audiobooks/` (issue #48): the path
//  guard's narrow exception, the planner (copy, keep, adopt, remove) and
//  the executor on a fake card.
//
//  SAFETY
//  Uses temporary folders as the Mac and the card; never the real Apple
//  Books folder or a real card.
//

import Foundation
import Testing
@testable import Q2SyncCore

/// A fake audiobook whose parts are real temp files of the given sizes.
private func makeBook(_ id: String, _ title: String, in mac: URL, parts: [(String, Int)],
                      availability: TrackAvailability = .available) throws -> Audiobook {
    let made = try parts.map { name, bytes -> AudiobookPart in
        let url = mac.appending(path: "\(id)-\(name)")
        try Data(repeating: UInt8(bytes % 251), count: bytes).write(to: url)
        return AudiobookPart(fileURL: url, trackNumber: 0, discNumber: 0, durationSeconds: 3600,
                             fileSize: UInt64(bytes))
    }
    // Card names come from the file name, so drop the id prefix there.
    let renamed = made.enumerated().map { index, part -> AudiobookPart in
        let target = mac.appending(path: id, directoryHint: .isDirectory).appending(path: parts[index].0)
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.moveItem(at: part.fileURL, to: target)
        return AudiobookPart(fileURL: target, trackNumber: 0, discNumber: 0, durationSeconds: 3600, fileSize: part.fileSize)
    }
    return Audiobook(id: id, title: title, author: nil, durationSeconds: 3600, parts: renamed,
                     availability: availability)
}

private let all = AudiobookSelection(isEnabled: true, includesAll: true)

private func plan(_ books: [Audiobook], _ selection: AudiobookSelection = all, card: TestCard,
                  manifest: SyncManifest? = nil) throws -> (AudiobookPlan, SyncManifest) {
    let manifest = try manifest ?? SyncManifest.load(from: card.fileSystem)
    let plan = AudiobookPlanner.plan(books: books, selection: selection, manifest: manifest,
                                     card: AudiobookCardListing.scan(on: card.fileSystem), folderName: "Audiobooks")
    return (plan, manifest)
}

/// Runs a sync made only of this audiobook plan.
private func run(_ audiobooks: AudiobookPlan, manifest: SyncManifest, card: TestCard,
                 removals: Bool = false) async throws -> SyncReport {
    let logs = try makeTempFolder()
    var syncPlan = SyncPlan()
    syncPlan.audiobooks = audiobooks
    var options = SyncOptions()
    options.applyRemovals = removals
    let executor = SyncExecutor(fileSystem: card.fileSystem, deviceName: "Test", logsDirectory: logs)
    return await executor.run(plan: syncPlan, manifest: manifest, options: options) { _ in }
}

private func write(_ card: TestCard, _ path: String, bytes: Int) throws {
    let url = card.root.appending(path: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: url)
}

@Suite("Audiobooks on the card: path guard")
struct AudiobookGuardTests {

    @Test("Q2 Pod: book folders and audio files directly inside them are allowed")
    func allowed() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let g = card.pathGuard
        _ = try g.check("Audiobooks", for: .createDirectory)
        _ = try g.check("Audiobooks/The Martian", for: .createDirectory)
        _ = try g.check("Audiobooks/The Martian/The Martian.m4b", for: .write)
        _ = try g.check("Audiobooks/Contact/01 Part 1.M4B", for: .write)
        _ = try g.check("Audiobooks/The Martian/The Martian.m4b", for: .delete)
        _ = try g.check("Audiobooks/The Martian", for: .delete)
    }

    @Test("Anything else in Audiobooks is refused", arguments: [
        ("Audiobooks/Loose.m4b", PathGuard.Operation.write),
        ("Audiobooks/Book/Sub/Part.m4b", .write),
        ("Audiobooks/Book/Sub", .createDirectory),
        ("Audiobooks/Book/cover.jpg", .write),
        ("Audiobooks/Book/notes.txt", .write),
        ("Audiobooks/Book/.hidden.m4b", .write),
        ("Audiobooks/.Book/Part.m4b", .write),
        ("Audiobooks/Book/database.ignore", .write),
        ("Audiobooks", .delete),
        ("Audiobooks/Book/Part.m4b", .deleteConfirmedByUser),
        ("Podcasts/Show/ep1.mp3", .write),
        ("EQ/Bass.txt", .write),
    ])
    func refused(path: String, operation: PathGuard.Operation) throws {
        let card = try TestCard(); defer { card.cleanUp() }
        #expect(throws: PathGuard.Violation.self) { try card.pathGuard.check(path, for: operation) }
    }

    @Test("Stock firmware: Audiobooks stays off limits")
    func stock() throws {
        let root = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let g = try PathGuard(cardRoot: root, expectedVolumeUUID: TestCard.uuid, profile: .stock,
                              homeMusicFolder: fakeHomeMusic,
                              volumeInfo: { _ in makeVolume(uuid: TestCard.uuid) })
        #expect(throws: PathGuard.Violation.self) { try g.check("Audiobooks/Book/Part.m4b", for: .write) }
        #expect(throws: PathGuard.Violation.self) { try g.check("Audiobooks", for: .createDirectory) }
    }

    @Test("Scanning the card still leaves Audiobooks out of music")
    func cardScan() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try write(card, "Audiobooks/Book/Part.m4b", bytes: 5)
        let wholeCard = CardScanner.scan(folder: "", on: card.fileSystem)
        #expect(wholeCard.isEmpty)
        let listing = AudiobookCardListing.scan(on: card.fileSystem)
        #expect(listing.files[CardLayout.caseKey("Audiobooks/Book/Part.m4b")]?.size == 5)
        #expect(listing.folders == [CardLayout.caseKey("Audiobooks/Book")])
    }
}

@Suite("Audiobooks on the card: planning")
struct AudiobookPlannerTests {

    @Test("Chosen books are copied into one folder each; protected ones are skipped")
    func copies() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let mac = try makeTempFolder()
        let martian = try makeBook("sha1-m", "The Martian", in: mac, parts: [("The Martian.m4b", 10)])
        let contact = try makeBook("5446582", "Contact", in: mac,
                                   parts: [("01 Part 1.m4b", 5), ("02 Part 2.m4b", 6)], availability: .drmProtected)
        let madd = try makeBook("sha1-a", "MaddAddam", in: mac, parts: [("Part 1.m4b", 3), ("Part 2.m4b", 4)])
        let (p, _) = try plan([martian, contact, madd], card: card)
        #expect(p.copies.map(\.destination) == ["Audiobooks/MaddAddam/Part 1.m4b", "Audiobooks/MaddAddam/Part 2.m4b",
                                                "Audiobooks/The Martian/The Martian.m4b"])
        #expect(p.booksToCopy == 2)
        #expect(p.bytesToCopy == 17)
        #expect(p.skipped.map(\.id) == ["5446582"])
        #expect(p.removals.isEmpty)
    }

    @Test("Books are counted once each as added or updated")
    func addAndUpdateCounts() {
        func copy(_ id: String, _ kind: AudiobookCopy.Kind, _ name: String) -> AudiobookCopy {
            AudiobookCopy(kind: kind, bookID: id, bookTitle: id, folder: "Audiobooks/\(id)",
                          source: URL(fileURLWithPath: "/tmp/\(name)"), sourceSize: 1,
                          destination: "Audiobooks/\(id)/\(name)")
        }
        var p = AudiobookPlan()
        // "new": two parts, both new. "changed": one part updated, one new.
        // "trimmed": only an old part replaced, plus a new part.
        p.copies = [copy("new", .add, "1.m4b"), copy("new", .add, "2.m4b"),
                    copy("changed", .update, "1.m4b"), copy("changed", .add, "2.m4b"),
                    copy("trimmed", .add, "3.m4b")]
        p.removals = [AudiobookRemoval(bookID: "trimmed", bookTitle: "trimmed", path: "Audiobooks/trimmed/old.m4b",
                                       cardSize: 1, isReplaced: true),
                      AudiobookRemoval(bookID: "gone", bookTitle: "gone", path: "Audiobooks/gone/a.m4b",
                                       cardSize: 1, isReplaced: false)]
        #expect(p.booksToCopy == 3)
        #expect(p.booksToAdd == 1)
        #expect(p.booksToUpdate == 2)
        #expect(p.booksToRemove == 1)
    }

    @Test("Off, or nothing ticked under Selected: nothing to copy")
    func nothingChosen() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let book = try makeBook("a", "A", in: try makeTempFolder(), parts: [("a.m4b", 1)])
        #expect(try plan([book], AudiobookSelection(), card: card).0.isEmpty)
        #expect(try plan([book], AudiobookSelection(isEnabled: true, includesAll: false), card: card).0.isEmpty)
    }

    @Test("A folder already on the card is never written into; the book gets “Title (2)”")
    func folderTaken() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try write(card, "Audiobooks/Dr. No/mine.mp3", bytes: 9)
        let book = try makeBook("a", "Dr. No", in: try makeTempFolder(), parts: [("Dr No.m4b", 4)])
        let p = try plan([book], card: card).0
        #expect(p.copies.map(\.destination) == ["Audiobooks/Dr. No (2)/Dr No.m4b"])
    }

    @Test("Two books with the same title get separate folders")
    func sameTitle() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let mac = try makeTempFolder()
        let a = try makeBook("a", "Dune", in: mac, parts: [("1.m4b", 1)])
        let b = try makeBook("b", "Dune", in: mac, parts: [("1.m4b", 2)])
        let folders = Set(try plan([a, b], card: card).0.copies.map(\.folder))
        #expect(folders == ["Audiobooks/Dune", "Audiobooks/Dune (2)"])
    }

    @Test("A book copied by hand with identical files is adopted, not copied again")
    func adoption() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try write(card, "Audiobooks/The Martian/The Martian.m4b", bytes: 10)
        let book = try makeBook("m", "The Martian", in: try makeTempFolder(), parts: [("The Martian.m4b", 10)])
        let p = try plan([book], card: card).0
        #expect(p.copies.isEmpty)
        #expect(p.adoptions["m"]?.folder == "Audiobooks/The Martian")
    }

    @Test("Synced books: unchanged, updated, a part dropped, a stranger's file kept")
    func existing() async throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let mac = try makeTempFolder()
        let book = try makeBook("b", "Book", in: mac, parts: [("1.m4b", 10), ("2.m4b", 20)])
        let (first, manifest) = try plan([book], card: card)
        #expect(try await run(first, manifest: manifest, card: card).succeeded)

        let (again, _) = try plan([book], card: card)
        #expect(again.isEmpty && again.unchangedBooks == 1)

        // Changed on the card → copied again.
        try write(card, "Audiobooks/Book/1.m4b", bytes: 3)
        #expect(try plan([book], card: card).0.copies.map(\.kind) == [.update])
        try write(card, "Audiobooks/Book/1.m4b", bytes: 10)

        // Apple Books now has only part 1: part 2 is removed with the update.
        let shorter = Audiobook(id: "b", title: "Book", author: nil, durationSeconds: 1,
                                parts: [book.parts[0]], availability: .available)
        let dropped = try plan([shorter], card: card).0
        #expect(dropped.replacedFiles.map(\.path) == ["Audiobooks/Book/2.m4b"])
        #expect(dropped.bookRemovals.isEmpty)

        // A new part whose name is taken by a file Q2 Sync didn't copy.
        try write(card, "Audiobooks/Book/3.m4b", bytes: 1)
        let three = try makeBook("x", "x", in: mac, parts: [("3.m4b", 7)]).parts[0]
        let longer = Audiobook(id: "b", title: "Book", author: nil, durationSeconds: 1,
                               parts: book.parts + [three], availability: .available)
        let blocked = try plan([longer], card: card).0
        #expect(blocked.copies.isEmpty)
        #expect(blocked.note != nil)
    }

    @Test("Books no longer chosen are removals; chosen-but-protected ones stay")
    func removals() async throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let mac = try makeTempFolder()
        let a = try makeBook("a", "A", in: mac, parts: [("a.m4b", 4)])
        let b = try makeBook("b", "B", in: mac, parts: [("b.m4b", 5)])
        let (first, manifest) = try plan([a, b], card: card)
        _ = try await run(first, manifest: manifest, card: card)

        let off = try plan([a, b], AudiobookSelection(), card: card).0
        #expect(off.booksToRemove == 2 && off.bookRemovals.allSatisfy { !$0.isReplaced })

        let goneFromBooks = try plan([a], card: card).0
        #expect(goneFromBooks.bookRemovals.map(\.bookID) == ["b"])

        let protectedNow = Audiobook(id: "b", title: "B", author: nil, durationSeconds: 1,
                                     parts: b.parts, availability: .drmProtected)
        #expect(try plan([a, protectedNow], card: card).0.removals.isEmpty)
    }

    @Test("If Apple Books lists nothing, nothing is removed")
    func emptyBooksRemovesNothing() async throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let a = try makeBook("a", "A", in: try makeTempFolder(), parts: [("a.m4b", 4)])
        let (first, manifest) = try plan([a], card: card)
        _ = try await run(first, manifest: manifest, card: card)
        let p = try plan([], card: card).0
        #expect(p.removals.isEmpty)
        #expect(p.note != nil)
    }

    @Test("Records whose files were deleted by hand are forgotten")
    func forgotten() async throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let mac = try makeTempFolder()
        let a = try makeBook("a", "A", in: mac, parts: [("a.m4b", 4)])
        let b = try makeBook("b", "B", in: mac, parts: [("b.m4b", 4)])
        let (first, manifest) = try plan([a, b], card: card)
        _ = try await run(first, manifest: manifest, card: card)
        try FileManager.default.removeItem(at: card.root.appending(path: "Audiobooks/A"))
        let p = try plan([b], card: card).0
        #expect(p.forgotten == ["a"])
        #expect(p.removals.isEmpty)
    }

    @Test("Folder names: a dot in a title isn't treated as an extension")
    func folderVariants() {
        #expect(AudiobookPlanner.freeFolder("Audiobooks/Dr. No", taken: [CardLayout.caseKey("Audiobooks/Dr. No")])
                == "Audiobooks/Dr. No (2)")
    }
}

@Suite("Audiobooks on the card: syncing")
struct AudiobookExecutorTests {

    @Test("Copying records the book; removing needs the user's choice and takes only Q2 Sync's files")
    func copyThenRemove() async throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let mac = try makeTempFolder()
        let book = try makeBook("c", "Contact", in: mac, parts: [("01 Part 1.m4b", 50), ("02 Part 2.m4b", 60)])
        let source = try Data(contentsOf: book.parts[0].fileURL)

        let (first, manifest) = try plan([book], card: card)
        let report = try await run(first, manifest: manifest, card: card)
        #expect(report.succeeded)
        #expect(report.audiobooksCopied == 1)
        #expect(try Data(contentsOf: card.root.appending(path: "Audiobooks/Contact/01 Part 1.m4b")) == source)
        #expect(try Data(contentsOf: book.parts[0].fileURL) == source, "Mac file untouched")
        let saved = try SyncManifest.load(from: card.fileSystem)
        #expect(saved.audiobooks?["c"]?.files.count == 2)
        #expect(saved.entries.isEmpty, "Not recorded as songs")

        // Someone else's file in the same folder.
        try write(card, "Audiobooks/Contact/notes.m4b", bytes: 3)

        // Turned off: kept unless removals are chosen.
        let (off, offManifest) = try plan([book], AudiobookSelection(), card: card)
        _ = try await run(off, manifest: offManifest, card: card, removals: false)
        #expect(FileManager.default.fileExists(atPath: card.root.appending(path: "Audiobooks/Contact/01 Part 1.m4b").path))

        let (off2, offManifest2) = try plan([book], AudiobookSelection(), card: card)
        let removed = try await run(off2, manifest: offManifest2, card: card, removals: true)
        #expect(removed.audiobooksRemoved == 1)
        #expect(!FileManager.default.fileExists(atPath: card.root.appending(path: "Audiobooks/Contact/01 Part 1.m4b").path))
        #expect(FileManager.default.fileExists(atPath: card.root.appending(path: "Audiobooks/Contact/notes.m4b").path))
        #expect(try SyncManifest.load(from: card.fileSystem).audiobooks?["c"] == nil)
    }

    @Test("A removed book's empty folder goes; Audiobooks itself stays")
    func emptyFolders() async throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let book = try makeBook("a", "A", in: try makeTempFolder(), parts: [("a.m4b", 4)])
        let (first, manifest) = try plan([book], card: card)
        _ = try await run(first, manifest: manifest, card: card)
        let (off, m2) = try plan([book], AudiobookSelection(), card: card)
        _ = try await run(off, manifest: m2, card: card, removals: true)
        #expect(!FileManager.default.fileExists(atPath: card.root.appending(path: "Audiobooks/A").path))
        #expect(FileManager.default.fileExists(atPath: card.root.appending(path: "Audiobooks").path))
    }

    @Test("Auto-sync stops for review before removing audiobooks")
    func autoSync() {
        var plan = SyncPlan()
        plan.audiobooks.removals = [AudiobookRemoval(bookID: "a", bookTitle: "A", path: "Audiobooks/A/a.m4b",
                                                     cardSize: 1, isReplaced: false)]
        guard case .needsReview = AutoSyncPolicy.decide(plan: plan, assessment: SafetyAssessment()) else {
            Issue.record("Expected review")
            return
        }
    }
}

@Suite("Audiobooks on the capacity bar")
struct AudiobookCapacityTests {

    @Test("Chosen books on the card, books to add, and books no longer chosen")
    func estimate() {
        var manifest = SyncManifest()
        manifest.audiobooks = [
            "kept": AudiobookRecord(folder: "Audiobooks/K", title: "K",
                                    files: [AudiobookFileRecord(path: "Audiobooks/K/k.m4b", sourceSize: 100, cardSize: 100, syncedAt: .now)]),
            "dropped": AudiobookRecord(folder: "Audiobooks/D", title: "D",
                                       files: [AudiobookFileRecord(path: "Audiobooks/D/d.m4b", sourceSize: 40, cardSize: 40, syncedAt: .now)]),
        ]
        func book(_ id: String, _ size: UInt64) -> Audiobook {
            Audiobook(id: id, title: id, author: nil, durationSeconds: 1,
                      parts: [AudiobookPart(fileURL: URL(filePath: "/\(id).m4b"), trackNumber: 0, discNumber: 0,
                                            durationSeconds: 1, fileSize: size)], availability: .available)
        }
        let books = [book("kept", 100), book("dropped", 40), book("new", 30)]
        let settings = AudiobookSelection(isEnabled: true, includesAll: false, bookIDs: ["kept", "new"])
        let estimate = CapacityEstimate.compute(totalBytes: 10_000_000_000, freeBytes: 9_000_000_000,
                                                manifest: manifest, selection: nil,
                                                audiobooks: (books, settings))
        #expect(estimate.audiobookBytes == 100)
        #expect(estimate.deselectedMusicBytes == 40)
        #expect(estimate.toAddBytes == 30)
        #expect(estimate.otherBytes == 1_000_000_000 - 140)
    }
}
