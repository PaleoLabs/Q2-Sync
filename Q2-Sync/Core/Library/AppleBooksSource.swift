//
//  AppleBooksSource.swift
//  Q2-Sync › Core › Library
//
//  PURPOSE
//  Reads the audiobooks in Apple Books, read-only, as `Audiobook` values.
//
//  WHERE APPLE BOOKS KEEPS THEM
//  ~/Library/Containers/com.apple.BKAgentService/Data/Documents/iBooks/Books/
//    • Books.plist: a dictionary whose `Books` array lists every book
//      (ebooks too). An audiobook has `BKBookType` = "audiobook", a title
//      (`itemName`), maybe an author (`artistName`), its length
//      (`BKDuration`, seconds) and `BKParts`: one entry per audio file with
//      its `path`, `BKTrackNumber`, `BKDiscNumber` and `BKDuration`.
//    • Audiobooks/<id>/<file>.m4b: the audio. `<id>` is `sha1-…` for books
//      you added and a number for store purchases.
//  Seen on macOS 27.2 with nine books (issue #48). `hasProtectedContent`
//  is never in Books.plist, so protection is checked on each file.
//
//  SAFETY
//  Reading only. The sandbox reaches this folder only through a read-only
//  bookmark the user granted. A part whose path isn't inside the folder is
//  never read or copied; its book is reported as not supported.
//
//  HOW IT FITS
//  The Audiobooks tab and the sync planner ask an `AudiobookSource` for
//  books. Tests use `FixtureAudiobookSource`, never the real Apple Books.
//

import AVFoundation
import Foundation

/// Something that can list audiobooks. Reading only.
protocol AudiobookSource: Sendable {

    /// Reads the audiobooks, sorted by title.
    ///
    /// - Throws: `AudiobookError` if the list can't be read.
    /// - Side effects: None. Reading only.
    func loadAudiobooks() async throws -> [Audiobook]

    /// The "looks healthy" check for books this source just read (see
    /// `AudiobookHealthCheck`).
    ///
    /// - Parameters:
    ///   - books: The books just read.
    ///   - selection: A Q2's choice, or `nil` for every book.
    func health(of books: [Audiobook], selection: AudiobookSelection?) -> LibraryHealth
}

extension AudiobookSource {

    /// Without a folder to check (fixtures), only the missing-files rule applies.
    func health(of books: [Audiobook], selection: AudiobookSelection?) -> LibraryHealth {
        AudiobookHealthCheck.evaluate(books, selection: selection, folder: nil)
    }
}

/// Problems reading Apple Books.
enum AudiobookError: LocalizedError, Equatable {

    /// Books.plist is missing (Apple Books never used on this Mac).
    case noBooksList

    /// Books.plist couldn't be read or isn't in the expected shape.
    case booksListUnreadable(underlying: String)

    var errorDescription: String? {
        switch self {
        case .noBooksList:
            return "Apple Books has no audiobooks on this Mac."
        case .booksListUnreadable(let underlying):
            return "Q2 Sync couldn't read Apple Books' list of books. (\(underlying))"
        }
    }
}

/// The real Apple Books library.
struct AppleBooksSource: AudiobookSource {

    /// Apple Books' folder (the one the user is asked to allow).
    static var defaultFolder: URL {
        PathGuard.realHomeDirectory.appending(
            path: "Library/Containers/com.apple.BKAgentService/Data/Documents/iBooks/Books",
            directoryHint: .isDirectory)
    }

    /// The list of books inside that folder.
    static let listFileName = "Books.plist"

    /// The Books folder, already accessible (security scope started).
    let folder: URL

    /// Answers "is this file protected?" (`nil` if it can't be read as
    /// audio). Replaceable for tests.
    let isProtected: @Sendable (URL) async -> Bool?

    init(folder: URL = AppleBooksSource.defaultFolder,
         isProtected: @escaping @Sendable (URL) async -> Bool? = AudiobookProtection.isProtected) {
        self.folder = folder
        self.isProtected = isProtected
    }

    func loadAudiobooks() async throws -> [Audiobook] {
        let listURL = folder.appending(path: Self.listFileName)
        let data: Data
        do {
            data = try Data(contentsOf: listURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw AudiobookError.noBooksList
        } catch {
            throw AudiobookError.booksListUnreadable(underlying: error.localizedDescription)
        }
        let entries = try BooksList.audiobookEntries(from: data, folder: folder)
        let isProtected = self.isProtected
        let folderPath = PathGuard.realPath(folder.path) ?? folder.standardizedFileURL.path

        let books = await withTaskGroup(of: Audiobook.self) { group in
            for entry in entries {
                group.addTask {
                    await BooksList.audiobook(from: entry, folderPath: folderPath, isProtected: isProtected)
                }
            }
            var books: [Audiobook] = []
            for await book in group { books.append(book) }
            return books
        }
        return BooksList.sorted(books)
    }

    func health(of books: [Audiobook], selection: AudiobookSelection?) -> LibraryHealth {
        AudiobookHealthCheck.evaluate(books, selection: selection, folder: folder)
    }
}

/// Asks macOS whether an audio file is copy-protected (FairPlay). This is
/// AVFoundation's own answer; it matched the Q2 for all nine test books,
/// where searching the file's bytes did not.
enum AudiobookProtection {

    /// `true` if protected, `false` if not, `nil` if the file can't be read
    /// as audio.
    @Sendable static func isProtected(_ url: URL) async -> Bool? {
        try? await AVURLAsset(url: url).load(.hasProtectedContent)
    }
}

/// Parsing of Books.plist, kept free of file access so it's easy to test.
enum BooksList {

    /// One audiobook entry as written in Books.plist, before its files are
    /// checked.
    struct Entry: Equatable, Sendable {
        let id: String
        let title: String
        let author: String?
        let durationSeconds: Double
        let parts: [Part]
    }

    /// One part as written in Books.plist.
    struct Part: Equatable, Sendable {
        let fileURL: URL
        let trackNumber: Int
        let discNumber: Int
        let durationSeconds: Double
        let recordedSize: UInt64
    }

    /// The audiobook entries in Books.plist (ebooks are left out), parts in
    /// playing order.
    ///
    /// - Parameters:
    ///   - data: Books.plist's contents.
    ///   - folder: The Books folder, for paths given relative to it.
    static func audiobookEntries(from data: Data, folder: URL) throws -> [Entry] {
        let root: Any
        do {
            root = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            throw AudiobookError.booksListUnreadable(underlying: error.localizedDescription)
        }
        guard let dict = root as? [String: Any], let books = dict["Books"] as? [[String: Any]] else {
            throw AudiobookError.booksListUnreadable(underlying: "no list of books")
        }
        return books.compactMap { entry(from: $0, folder: folder) }
    }

    /// One audiobook entry, or `nil` if this isn't an audiobook.
    static func entry(from book: [String: Any], folder: URL) -> Entry? {
        guard string(book["BKBookType"]) == "audiobook" else { return nil }
        let bookPath = string(book["path"]).map { fileURL($0, in: folder) }
        let folderName = bookPath?.lastPathComponent

        // A stable id: added books have `sha1-…`, store purchases an item id.
        guard let id = string(book["BKGeneratedItemId"]) ?? string(book["itemId"])
                ?? folderName ?? string(book["BKDisplayName"]) else { return nil }

        let title = string(book["itemName"]) ?? folderName ?? id
        let parts = ((book["BKParts"] as? [[String: Any]]) ?? []).compactMap { part -> Part? in
            guard let path = string(part["path"]) else { return nil }
            return Part(fileURL: fileURL(path, in: folder),
                        trackNumber: int(part["BKTrackNumber"]),
                        discNumber: int(part["BKDiscNumber"]),
                        durationSeconds: double(part["BKDuration"]),
                        recordedSize: UInt64(max(0, int(part["BKAllocatedSize"]))))
        }
        return Entry(id: id, title: title, author: string(book["artistName"]),
                     durationSeconds: double(book["BKDuration"]), parts: ordered(parts))
    }

    /// Playing order: disc, then track, then file name (Finder's order).
    /// Unknown numbers (0) sort first, so a lone "track 0" file stays put.
    static func ordered(_ parts: [Part]) -> [Part] {
        parts.sorted { a, b in
            if a.discNumber != b.discNumber { return a.discNumber < b.discNumber }
            if a.trackNumber != b.trackNumber { return a.trackNumber < b.trackNumber }
            return a.fileURL.lastPathComponent.localizedStandardCompare(b.fileURL.lastPathComponent)
                == .orderedAscending
        }
    }

    /// Checks an entry's files and builds the `Audiobook`.
    ///
    /// The order of checks matters, as for songs: a part outside the Books
    /// folder, or not an audio file we know, makes the whole book
    /// unsupported (and its files are never opened). Then DRM, which can
    /// only be checked on files that are there. Then missing files: none
    /// there means not downloaded; some means a file is missing.
    static func audiobook(from entry: Entry, folderPath: String,
                          isProtected: @Sendable (URL) async -> Bool?) async -> Audiobook {
        let fileManager = FileManager.default
        var parts: [AudiobookPart] = []
        var missing = 0
        var unsupported = entry.parts.isEmpty
        var protected = false

        for part in entry.parts {
            let path = part.fileURL.standardizedFileURL.path
            let real = PathGuard.resolve(path) ?? path
            let ext = part.fileURL.pathExtension.lowercased()
            var size = part.recordedSize
            if !PathGuard.isInside(real, folder: folderPath) || !CardScanner.audioExtensions.contains(ext) {
                unsupported = true  // never opened
            } else if let attributes = try? fileManager.attributesOfItem(atPath: path),
               (attributes[.type] as? FileAttributeType) == .typeRegular {
                size = (attributes[.size] as? NSNumber)?.uint64Value ?? size
                switch await isProtected(part.fileURL) {
                case true?: protected = true
                case false?: break
                case nil: unsupported = true
                }
            } else {
                missing += 1
            }
            parts.append(AudiobookPart(fileURL: part.fileURL, trackNumber: part.trackNumber,
                                       discNumber: part.discNumber,
                                       durationSeconds: part.durationSeconds, fileSize: size))
        }

        let availability: TrackAvailability
        if unsupported { availability = .unsupported }
        else if protected { availability = .drmProtected }
        else if missing == entry.parts.count { availability = .cloudOnly }
        else if missing > 0 { availability = .fileMissing }
        else { availability = .available }

        // A book's own length, or the sum of its parts if it has none.
        let duration = entry.durationSeconds > 0
            ? entry.durationSeconds : parts.reduce(0) { $0 + $1.durationSeconds }
        return Audiobook(id: entry.id, title: entry.title, author: entry.author,
                         durationSeconds: duration, parts: parts, availability: availability)
    }

    /// Books by title (Finder's order), then id so equal titles stay put.
    static func sorted(_ books: [Audiobook]) -> [Audiobook] {
        books.sorted { a, b in
            switch a.title.localizedStandardCompare(b.title) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return a.id < b.id
            }
        }
    }

    // MARK: - Plist value helpers

    private static func fileURL(_ path: String, in folder: URL) -> URL {
        path.hasPrefix("/") ? URL(filePath: path) : folder.appending(path: path)
    }

    private static func string(_ value: Any?) -> String? {
        let text: String?
        switch value {
        case let string as String: text = string
        case let number as NSNumber: text = number.stringValue
        default: text = nil
        }
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func int(_ value: Any?) -> Int {
        switch value {
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string) ?? 0
        default: return 0
        }
    }

    private static func double(_ value: Any?) -> Double {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string) ?? 0
        default: return 0
        }
    }
}

/// A fake audiobook library for tests and previews.
struct FixtureAudiobookSource: AudiobookSource {
    let books: [Audiobook]
    func loadAudiobooks() async throws -> [Audiobook] { BooksList.sorted(books) }
}
