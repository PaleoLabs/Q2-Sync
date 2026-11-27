//
//  AudiobookTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Unit tests for reading Apple Books' audiobooks (`AppleBooksSource`,
//  `BooksList`): which entries are audiobooks, ids and titles, part order,
//  and why a book can't be synced.
//
//  SAFETY
//  Each test builds its own fake Books folder (a Books.plist and small
//  fake audio files) in a temporary folder. Nothing reads the real Apple
//  Books folder, and protection is answered by a stand-in, not AVFoundation.
//  The sample entries copy the shapes seen in issue #48: books you added
//  (`sha1-…` folders), store purchases (number folders, `itemId`,
//  `Track 1.m4b`), two-part books, and missing author or genre.
//

import Foundation
import Testing
@testable import Q2SyncCore

/// Remembers which files the protection stand-in was asked about.
private actor ProtectionLog {
    var asked: [String] = []
    func add(_ name: String) { asked.append(name) }
}

/// A fake Apple Books folder in a temporary folder.
private struct FakeBooksFolder {
    let folder: URL

    init() throws {
        folder = try makeTempFolder().appending(path: "Books", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Writes a small file at `Audiobooks/<bookFolder>/<name>`, returning its path.
    @discardableResult
    func addFile(_ bookFolder: String, _ name: String, bytes: Int = 10) throws -> String {
        let dir = folder.appending(path: "Audiobooks/\(bookFolder)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: name)
        try Data(repeating: 0, count: bytes).write(to: url)
        return url.path
    }

    /// Where a file would be, without creating it.
    func path(_ bookFolder: String, _ name: String) -> String {
        folder.appending(path: "Audiobooks/\(bookFolder)/\(name)").path
    }

    func writeList(_ books: [[String: Any]]) throws {
        let root: [String: Any] = ["Version": 3, "Books": books, "Updates": [Any](), "Redacted": [Any]()]
        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try data.write(to: folder.appending(path: "Books.plist"))
    }

    /// Reads the folder; files whose names are in `protected` are protected,
    /// and those in `unreadable` can't be read as audio.
    func load(protected: Set<String> = [], unreadable: Set<String> = [],
              log: ProtectionLog = ProtectionLog()) async throws -> [Audiobook] {
        let source = AppleBooksSource(folder: folder) { url in
            await log.add(url.lastPathComponent)
            if unreadable.contains(url.lastPathComponent) { return nil }
            return protected.contains(url.lastPathComponent)
        }
        return try await source.loadAudiobooks()
    }
}

/// A Books.plist audiobook entry.
private func book(id: String? = nil, itemId: Any? = nil, title: String?, author: String? = nil,
                  folder: String, duration: Double = 3600,
                  parts: [(path: String, track: Int, disc: Int)]) -> [String: Any] {
    var entry: [String: Any] = [
        "BKBookType": "audiobook", "BKDuration": duration, "path": folder,
        "BKParts": parts.map { part -> [String: Any] in
            ["BKBookType": "audiobook-track", "path": part.path, "BKTrackNumber": part.track,
             "BKDiscNumber": part.disc, "BKDuration": duration / Double(max(1, parts.count)),
             "BKAllocatedSize": 999]
        },
    ]
    if let id { entry["BKGeneratedItemId"] = id; entry["BKDisplayName"] = id }
    if let itemId { entry["itemId"] = itemId }
    if let title { entry["itemName"] = title }
    if let author { entry["artistName"] = author }
    return entry
}

@Suite("Apple Books audiobooks")
struct AudiobookTests {

    @Test("Only audiobooks are read; ebooks are left out")
    func onlyAudiobooks() async throws {
        let books = try FakeBooksFolder()
        let file = try books.addFile("sha1-aaa", "The Martian.m4b")
        try books.writeList([
            ["BKBookType": "epub", "itemName": "An Ebook", "path": "/elsewhere/book.epub"],
            book(id: "sha1-aaa", title: "The Martian", author: "Andy Weir",
                 folder: books.folder.path + "/Audiobooks/sha1-aaa", parts: [(file, 1, 0)]),
        ])
        let result = try await books.load()
        #expect(result.map(\.title) == ["The Martian"])
        #expect(result.first?.id == "sha1-aaa")
        #expect(result.first?.author == "Andy Weir")
        #expect(result.first?.availability == .available)
    }

    @Test("Store purchases use their item id; titles fall back to the folder name")
    func idsAndTitles() async throws {
        let books = try FakeBooksFolder()
        let bought = try books.addFile("1462787542", "Track 1.m4b")
        let untitled = try books.addFile("sha1-bbb", "b.m4b")
        let noIDs = try books.addFile("folder-only", "c.m4b")
        try books.writeList([
            book(itemId: 1462787542, title: "No Place to Die", folder: books.folder.path + "/Audiobooks/1462787542",
                 parts: [(bought, 0, 0)]),
            book(id: "sha1-bbb", title: nil, folder: books.folder.path + "/Audiobooks/sha1-bbb",
                 parts: [(untitled, 0, 0)]),
            book(title: "Folder Only", folder: books.folder.path + "/Audiobooks/folder-only",
                 parts: [(noIDs, 0, 0)]),
        ])
        let result = try await books.load()
        let byTitle = Dictionary(uniqueKeysWithValues: result.map { ($0.title, $0) })
        #expect(byTitle["No Place to Die"]?.id == "1462787542")
        #expect(byTitle["sha1-bbb"]?.id == "sha1-bbb")
        #expect(byTitle["Folder Only"]?.id == "folder-only")
        #expect(byTitle["No Place to Die"]?.author == nil)
        #expect(byTitle["No Place to Die"]?.parts.first?.fileName == "Track 1.m4b")
    }

    @Test("Parts play in disc, track, then file-name order")
    func partOrder() async throws {
        let books = try FakeBooksFolder()
        let p2 = try books.addFile("sha1-m", "MaddAddam Part 2 of 2.m4b")
        let p1 = try books.addFile("sha1-m", "MaddAddam Part 1 of 2.m4b")
        let d2 = try books.addFile("5446582", "02 Contact Part 2 of 2.m4b")
        let d1 = try books.addFile("5446582", "01 Contact Part 1 of 2.m4b")
        let n10 = try books.addFile("sha1-n", "Part 10.m4b")
        let n9 = try books.addFile("sha1-n", "Part 9.m4b")
        try books.writeList([
            book(id: "sha1-m", title: "MaddAddam", folder: books.folder.path + "/Audiobooks/sha1-m",
                 parts: [(p2, 2, 0), (p1, 1, 0)]),
            book(itemId: "5446582", title: "Contact", folder: books.folder.path + "/Audiobooks/5446582",
                 parts: [(d2, 2, 1), (d1, 1, 1)]),
            book(id: "sha1-n", title: "Numbers", folder: books.folder.path + "/Audiobooks/sha1-n",
                 parts: [(n10, 0, 0), (n9, 0, 0)]),
        ])
        let result = try await books.load()
        let byTitle = Dictionary(uniqueKeysWithValues: result.map { ($0.title, $0.parts.map(\.fileName)) })
        #expect(byTitle["MaddAddam"] == ["MaddAddam Part 1 of 2.m4b", "MaddAddam Part 2 of 2.m4b"])
        #expect(byTitle["Contact"] == ["01 Contact Part 1 of 2.m4b", "02 Contact Part 2 of 2.m4b"])
        #expect(byTitle["Numbers"] == ["Part 9.m4b", "Part 10.m4b"])
    }

    @Test("A book with any protected part is protected")
    func protected() async throws {
        let books = try FakeBooksFolder()
        let a = try books.addFile("5446582", "01 Part 1.m4b")
        let b = try books.addFile("5446582", "02 Part 2.m4b")
        try books.writeList([
            book(itemId: 5446582, title: "Contact", folder: books.folder.path + "/Audiobooks/5446582",
                 parts: [(a, 1, 1), (b, 2, 1)]),
        ])
        let result = try await books.load(protected: ["02 Part 2.m4b"])
        #expect(result.first?.availability == .drmProtected)
    }

    @Test("No files on the Mac: not downloaded; some missing: file missing")
    func missingFiles() async throws {
        let books = try FakeBooksFolder()
        let there = try books.addFile("sha1-half", "1.m4b")
        try books.writeList([
            book(itemId: 1716754192, title: "In iCloud", folder: books.folder.path + "/Audiobooks/1716754192",
                 parts: [(books.path("1716754192", "Track 1.m4b"), 0, 0)]),
            book(id: "sha1-half", title: "Half There", folder: books.folder.path + "/Audiobooks/sha1-half",
                 parts: [(there, 1, 0), (books.path("sha1-half", "2.m4b"), 2, 0)]),
        ])
        let result = try await books.load()
        let byTitle = Dictionary(uniqueKeysWithValues: result.map { ($0.title, $0.availability) })
        #expect(byTitle["In iCloud"] == .cloudOnly)
        #expect(byTitle["Half There"] == .fileMissing)
    }

    @Test("A part outside the Books folder is never opened; its book is unsupported")
    func outsideFolder() async throws {
        let books = try FakeBooksFolder()
        let outside = try makeTempFolder().appending(path: "secret.m4b")
        try Data(repeating: 0, count: 10).write(to: outside)
        let escape = books.folder.path + "/Audiobooks/../../escape.m4b"
        try books.writeList([
            book(id: "sha1-x", title: "Outside", folder: books.folder.path + "/Audiobooks/sha1-x",
                 parts: [(outside.path, 1, 0)]),
            book(id: "sha1-y", title: "Escape", folder: books.folder.path + "/Audiobooks/sha1-y",
                 parts: [(escape, 1, 0)]),
        ])
        let log = ProtectionLog()
        let result = try await books.load(log: log)
        #expect(result.allSatisfy { $0.availability == .unsupported })
        #expect(await log.asked.isEmpty)
    }

    @Test("Unknown file types, unreadable audio and books with no parts are unsupported")
    func unsupported() async throws {
        let books = try FakeBooksFolder()
        let pdf = try books.addFile("sha1-p", "booklet.pdf")
        let bad = try books.addFile("sha1-q", "broken.m4b")
        try books.writeList([
            book(id: "sha1-p", title: "PDF", folder: books.folder.path + "/Audiobooks/sha1-p", parts: [(pdf, 1, 0)]),
            book(id: "sha1-q", title: "Broken", folder: books.folder.path + "/Audiobooks/sha1-q", parts: [(bad, 1, 0)]),
            book(id: "sha1-r", title: "Empty", folder: books.folder.path + "/Audiobooks/sha1-r", parts: []),
        ])
        let result = try await books.load(unreadable: ["broken.m4b"])
        #expect(result.count == 3)
        #expect(result.allSatisfy { $0.availability == .unsupported })
    }

    @Test("Relative part paths are read from the Books folder")
    func relativePaths() async throws {
        let books = try FakeBooksFolder()
        try books.addFile("sha1-rel", "a.m4b")
        try books.writeList([
            book(id: "sha1-rel", title: "Relative", folder: "Audiobooks/sha1-rel",
                 parts: [("Audiobooks/sha1-rel/a.m4b", 1, 0)]),
        ])
        let result = try await books.load()
        #expect(result.first?.availability == .available)
    }

    @Test("Sizes come from the files; length falls back to the parts'")
    func sizesAndLength() async throws {
        let books = try FakeBooksFolder()
        let a = try books.addFile("sha1-s", "a.m4b", bytes: 100)
        let b = try books.addFile("sha1-s", "b.m4b", bytes: 50)
        var entry = book(id: "sha1-s", title: "Sized", folder: books.folder.path + "/Audiobooks/sha1-s",
                         duration: 7200, parts: [(a, 1, 0), (b, 2, 0)])
        entry["BKDuration"] = nil
        try books.writeList([entry])
        let result = try await books.load()
        #expect(result.first?.totalSize == 150)
        #expect(result.first?.durationSeconds == 7200)
    }

    @Test("Books are sorted by title, numbers in natural order")
    func sortedByTitle() async throws {
        let books = try FakeBooksFolder()
        var list: [[String: Any]] = []
        for title in ["Year of the Flood", "Book 10", "artemis", "Book 9"] {
            let id = "sha1-\(title.hashValue)"
            let file = try books.addFile(id, "f.m4b")
            list.append(book(id: id, title: title, folder: books.folder.path + "/Audiobooks/\(id)", parts: [(file, 1, 0)]))
        }
        try books.writeList(list)
        let result = try await books.load()
        #expect(result.map(\.title) == ["artemis", "Book 9", "Book 10", "Year of the Flood"])
    }

    @Test("No Books.plist, or a damaged one, is reported")
    func listErrors() async throws {
        let books = try FakeBooksFolder()
        await #expect(throws: AudiobookError.noBooksList) { try await books.load() }
        try Data("not a plist".utf8).write(to: books.folder.appending(path: "Books.plist"))
        await #expect(throws: AudiobookError.self) { try await books.load() }
        let noBooks = try PropertyListSerialization.data(fromPropertyList: ["Version": 3], format: .xml, options: 0)
        try noBooks.write(to: books.folder.appending(path: "Books.plist"))
        await #expect(throws: AudiobookError.booksListUnreadable(underlying: "no list of books")) { try await books.load() }
    }

    @Test("A part over 35 hours is flagged as possibly too long for Q2 Pod")
    func longPart() {
        func make(hours: Double) -> Audiobook {
            Audiobook(id: "x", title: "x", author: nil, durationSeconds: hours * 3600,
                      parts: [AudiobookPart(fileURL: URL(filePath: "/x.m4b"), trackNumber: 0, discNumber: 0,
                                            durationSeconds: hours * 3600, fileSize: 1)],
                      availability: .available)
        }
        #expect(!make(hours: 16.2).hasLongPart)
        #expect(make(hours: 40).hasLongPart)
    }
}

@Suite("Audiobook selection")
struct AudiobookSelectionTests {

    private func make(_ id: String, _ availability: TrackAvailability = .available) -> Audiobook {
        Audiobook(id: id, title: id, author: nil, durationSeconds: 3600,
                  parts: [AudiobookPart(fileURL: URL(filePath: "/\(id).m4b"), trackNumber: 0, discNumber: 0,
                                        durationSeconds: 3600, fileSize: 10)],
                  availability: availability)
    }

    private var library: [Audiobook] {
        [make("a"), make("b"), make("drm", .drmProtected), make("icloud", .cloudOnly)]
    }

    @Test("Off by default: nothing is copied")
    func offByDefault() {
        #expect(AudiobookSelection().books(from: library).isEmpty)
    }

    @Test("All: every available book, never protected or not-downloaded ones")
    func all() {
        let selection = AudiobookSelection(isEnabled: true, includesAll: true)
        #expect(selection.books(from: library).map(\.id) == ["a", "b"])
        #expect(!selection.isTicked(make("drm", .drmProtected)))
    }

    @Test("Selected: only ticked, available books")
    func selected() {
        var selection = AudiobookSelection(isEnabled: true, includesAll: false)
        selection.setTicked(true, ids: ["b", "drm"], in: library)
        #expect(selection.bookIDs == ["b"], "A protected book can't be ticked")
        #expect(selection.books(from: library).map(\.id) == ["b"])
        selection.setTicked(false, ids: ["b"], in: library)
        #expect(selection.books(from: library).isEmpty)
    }

    @Test("Ticks are ignored under All, and kept for switching back to Selected")
    func ticksUnderAll() {
        var selection = AudiobookSelection(isEnabled: true, includesAll: false, bookIDs: ["a"])
        selection.includesAll = true
        selection.setTicked(true, ids: ["b"], in: library)
        #expect(selection.bookIDs == ["a"])
        selection.includesAll = false
        #expect(selection.books(from: library).map(\.id) == ["a"])
    }

    @Test("A ticked book that's later protected or gone isn't copied")
    func tickedButUnavailable() {
        let selection = AudiobookSelection(isEnabled: true, includesAll: false, bookIDs: ["drm", "gone"])
        #expect(selection.books(from: library).isEmpty)
    }

    @Test("Saved Q2 settings without audiobooks load with audiobooks off")
    func oldSettingsLoad() throws {
        let device = KnownDevice(volumeUUID: "U", name: "Q2", firmware: .q2Pod, bookmarkData: Data(),
                                 addedDate: .now, hasCompletedFirstSync: true)
        let json = try JSONEncoder().encode(device)
        #expect(!String(decoding: json, as: UTF8.self).contains("audiobooks"))
        let loaded = try JSONDecoder().decode(KnownDevice.self, from: json)
        #expect(loaded.effectiveAudiobooks == AudiobookSelection())
        let partial = try JSONDecoder().decode(AudiobookSelection.self, from: Data(#"{"isEnabled":true}"#.utf8))
        #expect(partial == AudiobookSelection(isEnabled: true))
    }

    @Test("Audiobook edits go through Revert / Apply like music")
    func revertApply() {
        var changes = UnappliedChanges()
        var q2 = KnownDevice(volumeUUID: "U", name: "Q2", firmware: .q2Pod, bookmarkData: Data(),
                             addedDate: .now, hasCompletedFirstSync: true)
        changes.edit(q2) { $0.audiobooks.isEnabled = true }
        #expect(changes.hasChanges(for: q2))
        #expect(!q2.effectiveAudiobooks.isEnabled, "Saved settings untouched")

        changes.edit(q2) { $0.audiobooks.isEnabled = false }
        #expect(!changes.hasChanges(for: q2), "Turned back off: no change")

        changes.edit(q2) { $0.audiobooks.isEnabled = true }
        q2.audiobooks = changes.changes(for: q2)?.audiobooks  // Apply
        changes.discard(volumeUUID: "U")
        #expect(q2.syncSettings.audiobooks.isEnabled)
        #expect(!changes.hasChanges(for: q2))
    }
}
