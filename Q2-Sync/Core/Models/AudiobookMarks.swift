//
//  AudiobookMarks.swift
//  Q2-Sync › Core › Models
//
//  PURPOSE
//  Where each audiobook stands relative to a Q2, for the sidebar's Books
//  browser: on the Q2, copied at the next sync, not chosen, or can't sync.
//  The audiobook counterpart of `LibraryMarks`. Also says when the
//  sidebar's Audiobooks section shows (#70).
//
//  HOW IT FITS
//  Built by `AudiobookBrowserView` from the books in Apple Books, the
//  Mac-side record of the card (`CardContentsRecord.audiobookIDs`) and the
//  Q2's saved audiobook settings. Read-only: nothing here plans a sync.
//

import Foundation

/// Audiobook marks for the Books browser.
struct AudiobookMarks: Sendable, Equatable {

    /// Books on the Q2, or `nil` when there's no record of its books
    /// (no Q2 read yet, or a record saved before audiobooks were recorded).
    let onQ2IDs: Set<String>?

    /// The Q2's saved audiobook settings, or `nil` without a Q2.
    let selection: AudiobookSelection?

    /// `true` when there's a Q2's books to compare with.
    var hasQ2: Bool { onQ2IDs != nil }

    /// Builds the marks.
    ///
    /// - Parameters:
    ///   - record: The Q2's last known contents, if any.
    ///   - selection: Its saved audiobook settings, if any.
    init(record: CardContentsRecord?, selection: AudiobookSelection?) {
        onQ2IDs = record?.audiobookIDs
        self.selection = onQ2IDs == nil ? nil : selection
    }

    /// Where one book stands, or `nil` when there's no Q2 to compare with
    /// and the book can be copied.
    func placement(of book: Audiobook) -> TrackPlacement? {
        // A book can be on the card yet no longer copyable (removed from
        // Books, say); the card still has it.
        if onQ2IDs?.contains(book.id) == true { return .onQ2 }
        guard book.availability == .available else { return .cantSync }
        guard onQ2IDs != nil else { return nil }
        return selection?.includes(book) == true ? .nextSync : .notChosen
    }
}

extension Sequence where Element == KnownDevice {

    /// `true` when any of these Q2s syncs audiobooks. The sidebar shows its
    /// Audiobooks section then: "any", not "the selected one", so the
    /// sidebar stays put when you click between Q2s (decided on #70).
    var anySyncsAudiobooks: Bool {
        contains { $0.effectiveAudiobooks.isEnabled }
    }
}
