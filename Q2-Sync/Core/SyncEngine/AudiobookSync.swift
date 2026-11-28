//
//  AudiobookSync.swift
//  Q2-Sync › Core › SyncEngine
//
//  PURPOSE
//  Plans the audiobook part of a sync (issue #48): which books to copy to
//  the card, which are already there, and which Q2 Sync copied earlier
//  but are no longer wanted.
//
//  ON THE CARD (Q2 Pod only)
//      Audiobooks/<book title>/<part file name>
//      e.g.  Audiobooks/The Martian/The Martian - Andy Weir.m4b
//            Audiobooks/Contact/01 Contact Part 1 of 2.m4b
//  `Audiobooks/` gives Q2 Pod's Library its Audiobooks row: books resume,
//  have chapters, and stay out of music lists and shuffle. One folder per
//  book; parts keep their file names (sanitised for the card).
//
//  SAFETY
//  • `Audiobooks/` is a reserved folder; `PathGuard` lets Q2 Sync change
//    only `Audiobooks/<book>/<audio file>` there, and only on Q2 Pod.
//  • Q2 Sync records every book it copies in the manifest
//    (`SyncManifest.audiobooks`) and only ever replaces or removes files
//    recorded there. Anything else in `Audiobooks/` is left alone; a new
//    book never goes into a folder that's already there, unless that
//    folder already holds exactly the book's files (then they're adopted).
//  • Removing a book that's no longer wanted is a removal like a song's:
//    only when the user ticks "remove" in the review sheet, never in an
//    automatic sync. A book that's chosen but can't be copied right now
//    (protected, not downloaded) stays on the card.
//  • If Apple Books lists no audiobooks at all while the card has books
//    Q2 Sync copied, nothing is removed (Books may not have been read).
//
//  HOW IT FITS
//  `SyncCoordinator` scans `Audiobooks/`, calls `AudiobookPlanner.plan`
//  and stores the result in `SyncPlan.audiobooks`; `SyncExecutor` applies
//  it after the songs.
//

import Foundation

// MARK: - Manifest records

/// A book Q2 Sync put on the card.
struct AudiobookRecord: Codable, Sendable, Hashable {
    /// Its folder, e.g. `Audiobooks/The Martian`.
    var folder: CardPath
    /// Its title when copied (names it in reports after it leaves Books).
    var title: String
    /// Its files on the card.
    var files: [AudiobookFileRecord]
}

/// One file of a book Q2 Sync put on the card.
struct AudiobookFileRecord: Codable, Sendable, Hashable {
    var path: CardPath
    /// The Mac file's size when copied.
    var sourceSize: UInt64
    /// The card file's size after copying.
    var cardSize: UInt64
    var syncedAt: Date
}

// MARK: - Card listing

/// The card's `Audiobooks/` listing (the same shape serves `Podcasts/`).
typealias AudiobookCardListing = CardFolderListing

/// What's in a two-level content folder on the card: `Audiobooks/` or
/// `Podcasts/`.
struct CardFolderListing: Sendable, Equatable {
    /// Files at `<Folder>/<folder>/<file>`, keyed by `CardLayout.caseKey`.
    var files: [String: CardFile] = [:]
    /// Folders directly inside the top folder, as `caseKey`s of their paths.
    var folders: Set<String> = []

    /// Lists `Audiobooks/` two levels deep. Hidden items are skipped.
    ///
    /// - Side effects: None (reads directory listings and sizes only).
    static func scan(on fileSystem: CardFileSystem) -> CardFolderListing {
        scan(folderName: fileSystem.pathGuard.profile.audiobooksFolderName, on: fileSystem)
    }

    /// Lists a top folder (e.g. `Podcasts`) two levels deep. Hidden items
    /// are skipped; `nil` gives an empty listing.
    ///
    /// - Side effects: None (reads directory listings and sizes only).
    static func scan(folderName: String?, on fileSystem: CardFileSystem) -> CardFolderListing {
        var listing = CardFolderListing()
        guard let name = folderName else { return listing }
        let root = fileSystem.pathGuard.cardRoot.appending(path: name, directoryHint: .isDirectory)
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let books = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys,
                                                      options: [.skipsHiddenFiles]) else { return listing }
        for book in books {
            let values = try? book.resourceValues(forKeys: Set(keys))
            guard values?.isSymbolicLink != true, values?.isDirectory == true else { continue }
            let folder = "\(name)/\(book.lastPathComponent)".precomposedStringWithCanonicalMapping
            listing.folders.insert(CardLayout.caseKey(folder))
            guard let files = try? fm.contentsOfDirectory(at: book, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles]) else { continue }
            for file in files {
                let values = try? file.resourceValues(forKeys: Set(keys))
                guard values?.isSymbolicLink != true, values?.isRegularFile == true else { continue }
                let path = "\(folder)/\(file.lastPathComponent)".precomposedStringWithCanonicalMapping
                listing.files[CardLayout.caseKey(path)] = CardFile(path: path, size: UInt64(values?.fileSize ?? 0))
            }
        }
        return listing
    }
}

// MARK: - Plan

/// Copying one audiobook file to the card.
struct AudiobookCopy: Sendable, Hashable, Identifiable {
    enum Kind: String, Sendable { case add, update }
    let kind: Kind
    let bookID: String
    let bookTitle: String
    /// The book's folder on the card.
    let folder: CardPath
    let source: URL
    let sourceSize: UInt64
    let destination: CardPath
    var id: CardPath { destination }
}

/// Removing one file Q2 Sync copied earlier.
struct AudiobookRemoval: Sendable, Hashable, Identifiable {
    let bookID: String
    let bookTitle: String
    let path: CardPath
    let cardSize: UInt64
    /// `true` if the book is still wanted and this file is just no longer
    /// one of its parts: removed with the book's update, without asking.
    let isReplaced: Bool
    var id: CardPath { path }
}

/// The audiobook part of a sync.
struct AudiobookPlan: Sendable, Equatable {
    var copies: [AudiobookCopy] = []
    /// Files of books no longer wanted, and replaced files of wanted books.
    var removals: [AudiobookRemoval] = []
    /// Books whose files are already in their folder: recorded, not copied.
    var adoptions: [String: AudiobookRecord] = [:]
    /// Records whose files are all gone and whose book isn't wanted.
    var forgotten: [String] = []
    /// Wanted books already on the card as they are.
    var unchangedBooks = 0
    /// Chosen books that can't be copied (protected, not downloaded…).
    var skipped: [Audiobook] = []
    /// Set when books weren't planned at all, e.g. Apple Books couldn't be
    /// read. Shown in the review sheet; nothing on the card changes.
    var note: String?

    var bytesToCopy: UInt64 { copies.reduce(0) { $0 + $1.sourceSize } }
    /// Removals that need the user's "remove" choice.
    var bookRemovals: [AudiobookRemoval] { removals.filter { !$0.isReplaced } }
    /// Removals done as part of updating a wanted book.
    var replacedFiles: [AudiobookRemoval] { removals.filter(\.isReplaced) }
    var bytesFreedByRemovals: UInt64 { bookRemovals.reduce(0) { $0 + $1.cardSize } }
    /// Books to add or update, counted once each.
    var booksToCopy: Int { Set(copies.map(\.bookID)).count }
    var booksToRemove: Int { Set(bookRemovals.map(\.bookID)).count }
    /// Books being updated: any part copied over an older one, or any old
    /// part replaced. Each book counted once.
    var booksToUpdate: Int { updatedBookIDs.count }
    /// Books copied for the first time.
    var booksToAdd: Int { Set(copies.map(\.bookID)).subtracting(updatedBookIDs).count }

    private var updatedBookIDs: Set<String> {
        Set(copies.filter { $0.kind == .update }.map(\.bookID)).union(replacedFiles.map(\.bookID))
    }

    var isEmpty: Bool {
        copies.isEmpty && removals.isEmpty && adoptions.isEmpty && forgotten.isEmpty
    }
}

/// Builds the audiobook plan. Pure: changes nothing.
enum AudiobookPlanner {

    /// - Parameters:
    ///   - books: Every audiobook in Apple Books (any availability).
    ///   - selection: The Q2's Audiobooks settings.
    ///   - manifest: The card's manifest.
    ///   - card: What's in `Audiobooks/` now.
    ///   - folderName: The profile's audiobooks folder (`Audiobooks`).
    static func plan(books: [Audiobook], selection: AudiobookSelection, manifest: SyncManifest,
                     card: AudiobookCardListing, folderName: String) -> AudiobookPlan {
        var plan = AudiobookPlan()
        let records = manifest.audiobooks ?? [:]
        let wanted = selection.books(from: books)
        let wantedIDs = Set(wanted.map(\.id))
        // Chosen but not copyable now: kept on the card, never removed.
        plan.skipped = selection.isEnabled ? books.filter {
            $0.availability != .available && (selection.includesAll || selection.bookIDs.contains($0.id))
        } : []
        let keepIDs = wantedIDs.union(plan.skipped.map(\.id))

        // Folders spoken for: everything in Audiobooks/ now, plus every
        // recorded book's folder (even if it's gone from the card).
        var takenFolders = card.folders
        for record in records.values { takenFolders.insert(CardLayout.caseKey(record.folder)) }

        for book in wanted {
            if let record = records[book.id] {
                planExisting(book, record: record, card: card, into: &plan)
            } else {
                let preferred = "\(folderName)/" + FilenameSanitizer.sanitizeComponent(book.title, fallback: "Audiobook")
                let names = partNames(book)
                // The user copied this book there already: adopt it.
                if card.folders.contains(CardLayout.caseKey(preferred)),
                   !records.values.contains(where: { CardLayout.caseKey($0.folder) == CardLayout.caseKey(preferred) }),
                   let adopted = adoption(book, folder: preferred, names: names, card: card) {
                    plan.adoptions[book.id] = adopted
                    continue
                }
                let folder = freeFolder(preferred, taken: takenFolders)
                takenFolders.insert(CardLayout.caseKey(folder))
                for (part, name) in zip(book.parts, names) {
                    plan.copies.append(AudiobookCopy(kind: .add, bookID: book.id, bookTitle: book.title,
                                                     folder: folder, source: part.fileURL,
                                                     sourceSize: part.fileSize, destination: "\(folder)/\(name)"))
                }
            }
        }

        // Books Q2 Sync copied that are no longer wanted.
        let booksReadable = !books.isEmpty || records.isEmpty
        if !booksReadable {
            plan.note = "Apple Books listed no audiobooks, so none were removed from the card."
        }
        for (id, record) in records where !keepIDs.contains(id) {
            let present = record.files.filter { card.files[CardLayout.caseKey($0.path)] != nil }
            if present.isEmpty {
                plan.forgotten.append(id)
            } else if booksReadable {
                plan.removals += present.map {
                    AudiobookRemoval(bookID: id, bookTitle: record.title, path: $0.path,
                                     cardSize: card.files[CardLayout.caseKey($0.path)]?.size ?? $0.cardSize,
                                     isReplaced: false)
                }
            }
        }
        plan.copies.sort { SortKey.compare($0.destination, $1.destination) }
        plan.removals.sort { SortKey.compare($0.path, $1.path) }
        plan.forgotten.sort()
        return plan
    }

    /// A wanted book Q2 Sync copied before: keep its folder; copy parts
    /// that are new, changed or missing; remove files no longer its parts.
    private static func planExisting(_ book: Audiobook, record: AudiobookRecord,
                                     card: AudiobookCardListing, into plan: inout AudiobookPlan) {
        var recorded: [String: AudiobookFileRecord] = [:]
        for file in record.files { recorded[CardLayout.caseKey(file.path)] = file }
        var expected = Set<String>()
        var changed = false
        for (part, name) in zip(book.parts, partNames(book)) {
            let path = "\(record.folder)/\(name)"
            let key = CardLayout.caseKey(path)
            expected.insert(key)
            let onCard = card.files[key]
            if let file = recorded[key], let onCard, onCard.size == file.cardSize, file.sourceSize == part.fileSize {
                continue
            }
            // Never overwrite a file Q2 Sync didn't put there.
            if recorded[key] == nil, onCard != nil {
                plan.note = plan.note ?? "Some audiobook files weren't copied: files Q2 Sync didn't put there already have their names."
                continue
            }
            changed = true
            plan.copies.append(AudiobookCopy(kind: recorded[key] == nil ? .add : .update, bookID: book.id,
                                             bookTitle: book.title, folder: record.folder, source: part.fileURL,
                                             sourceSize: part.fileSize, destination: path))
        }
        for file in record.files where !expected.contains(CardLayout.caseKey(file.path)) {
            guard let onCard = card.files[CardLayout.caseKey(file.path)] else { continue }
            changed = true
            plan.removals.append(AudiobookRemoval(bookID: book.id, bookTitle: book.title, path: file.path,
                                                  cardSize: onCard.size, isReplaced: true))
        }
        if !changed { plan.unchangedBooks += 1 }
    }

    /// The record for a book already in `folder`, if every part is there
    /// with the same size; otherwise `nil`.
    private static func adoption(_ book: Audiobook, folder: CardPath, names: [String],
                                 card: AudiobookCardListing) -> AudiobookRecord? {
        var files: [AudiobookFileRecord] = []
        for (part, name) in zip(book.parts, names) {
            let path = "\(folder)/\(name)"
            guard let onCard = card.files[CardLayout.caseKey(path)], onCard.size == part.fileSize else { return nil }
            files.append(AudiobookFileRecord(path: onCard.path, sourceSize: part.fileSize,
                                             cardSize: onCard.size, syncedAt: .now))
        }
        return files.isEmpty ? nil : AudiobookRecord(folder: folder, title: book.title, files: files)
    }

    /// Card file names for a book's parts, sanitised, with " (2)" added if
    /// two parts would share a name.
    static func partNames(_ book: Audiobook) -> [String] {
        var used = Set<String>()
        return book.parts.map { part in
            let url = part.fileURL
            var name = FilenameSanitizer.sanitizeFileName(base: url.deletingPathExtension().lastPathComponent,
                                                          fileExtension: url.pathExtension)
            var number = 2
            let original = name
            while used.contains(CardLayout.caseKey(name)) {
                name = CardLayout.variant(of: original, number: number)
                number += 1
            }
            used.insert(CardLayout.caseKey(name))
            return name
        }
    }

    /// `preferred` if free, else "Title (2)", "Title (3)"… (a folder name
    /// has no extension, so a title like "Dr. No" keeps its dot).
    static func freeFolder(_ preferred: CardPath, taken: Set<String>) -> CardPath {
        if !taken.contains(CardLayout.caseKey(preferred)) { return preferred }
        var number = 2
        while true {
            let suffix = " (\(number))"
            let slash = preferred.lastIndex(of: "/").map { preferred.index(after: $0) } ?? preferred.startIndex
            let parent = String(preferred[..<slash])
            let name = FilenameSanitizer.truncate(String(preferred[slash...]),
                                                  maximumBytes: FilenameSanitizer.maximumComponentBytes - suffix.utf8.count)
            let candidate = parent + name + suffix
            if !taken.contains(CardLayout.caseKey(candidate)) { return candidate }
            number += 1
        }
    }
}
