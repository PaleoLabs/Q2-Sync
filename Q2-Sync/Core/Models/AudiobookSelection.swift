//
//  AudiobookSelection.swift
//  Q2-Sync › Core › Models
//
//  PURPOSE
//  What a Q2's Audiobooks tab is set to: like Finder's, "Sync audiobooks"
//  on or off, then all audiobooks or only the ticked ones.
//
//  HOW IT FITS
//  Saved per Q2 in `KnownDevice.audiobooks` and part of
//  `DeviceSyncSettings`, so Revert and Apply cover it. Books are
//  remembered by `Audiobook.id`, which stays the same across reads.
//  Only books that are `.available` are ever chosen: a protected or
//  not-downloaded book can't be ticked, and isn't copied under "All".
//

import Foundation

/// The Audiobooks tab's settings for one Q2.
struct AudiobookSelection: Codable, Hashable, Sendable {

    /// "Sync audiobooks onto [Q2]". Off by default: nothing changes on the
    /// card until the user turns it on.
    var isEnabled = false

    /// `true`: all audiobooks (books added later come too).
    /// `false`: only the books in `bookIDs`.
    var includesAll = true

    /// The ticked books when `includesAll` is off. Kept while "All" is on,
    /// so switching back to "Selected" brings the ticks back, as in Finder.
    var bookIDs: Set<String> = []

    init(isEnabled: Bool = false, includesAll: Bool = true, bookIDs: Set<String> = []) {
        self.isEnabled = isEnabled
        self.includesAll = includesAll
        self.bookIDs = bookIDs
    }

    /// `true` if this book is copied to the Q2.
    func includes(_ book: Audiobook) -> Bool {
        isEnabled && book.availability == .available && (includesAll || bookIDs.contains(book.id))
    }

    /// The books to copy, in the order given.
    func books(from all: [Audiobook]) -> [Audiobook] {
        all.filter(includes)
    }

    /// `true` if the book's tick box shows ticked (dimmed books never do).
    func isTicked(_ book: Audiobook) -> Bool {
        book.availability == .available && (includesAll || bookIDs.contains(book.id))
    }

    /// Ticks or unticks books under "Selected". Ignored under "All" (the
    /// tick boxes are dimmed then) and for books that can't be synced.
    mutating func setTicked(_ ticked: Bool, ids: Set<String>, in all: [Audiobook]) {
        guard !includesAll else { return }
        let available = Set(all.filter { $0.availability == .available }.map(\.id))
        let changed = ids.intersection(available)
        if ticked { bookIDs.formUnion(changed) } else { bookIDs.subtract(changed) }
    }

    // Missing keys decode to their defaults, so later additions don't
    // break settings saved by this version.
    private enum CodingKeys: String, CodingKey { case isEnabled, includesAll, bookIDs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        includesAll = try c.decodeIfPresent(Bool.self, forKey: .includesAll) ?? true
        bookIDs = try c.decodeIfPresent(Set<String>.self, forKey: .bookIDs) ?? []
    }
}
