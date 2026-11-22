//
//  LibraryMarks.swift
//  Q2-Sync › Core › Models
//
//  PURPOSE
//  Works out the marks the library browser shows: for each song, whether
//  it can be copied and where it stands on a Q2 (on it, coming at the next
//  sync, or not chosen); for each artist, album, genre or playlist, the
//  counts behind lines like "12 of 14 can sync" or "8 of 12 on Q2".
//
//  HOW IT FITS
//  Built once per library read / Q2 record / selection (it resolves the
//  selection, which walks the whole library), then asked about many rows.
//  The Q2 part comes from `CardContentsRecord`, the Mac-side note of the
//  card, so it's "as of" that record's date. Pure computation.
//

import Foundation

/// Where a song stands relative to a Q2.
enum TrackPlacement: Sendable, Equatable {
    /// Q2 Sync put it on the card (as of the record).
    case onQ2
    /// Chosen for this Q2 and copyable, but not on the card yet.
    case nextSync
    /// Copyable, but not chosen for this Q2.
    case notChosen
    /// Can't be copied at all (see the track's availability).
    case cantSync
}

/// Counts for one group (artist, album, genre, playlist).
struct GroupMarks: Sendable, Equatable {
    /// Songs in the group.
    var total = 0
    /// Songs that can be copied.
    var syncable = 0
    /// Songs on the Q2 (as of the record).
    var onQ2 = 0
    /// Chosen, copyable songs not on the Q2 yet.
    var nextSync = 0
}

/// Song and group marks for the library browser.
struct LibraryMarks: Sendable {

    /// Songs that can be copied.
    private let syncableIDs: Set<PersistentID>

    /// Songs on the Q2, or `nil` when there's no Q2 record.
    private let onQ2IDs: Set<PersistentID>?

    /// Copyable songs the Q2's selection includes, or `nil` without a Q2.
    private let chosenIDs: Set<PersistentID>?

    /// `true` when there's a Q2 record to compare with.
    var hasQ2: Bool { onQ2IDs != nil }

    /// Builds the marks.
    ///
    /// - Parameters:
    ///   - snapshot: The library.
    ///   - record: The Q2's last known contents, if any.
    ///   - selection: What's chosen for that Q2, if any.
    init(snapshot: LibrarySnapshot, record: CardContentsRecord?, selection: SyncSelection?) {
        syncableIDs = Set(snapshot.tracks.lazy.filter(\.isCopyable).map(\.id))
        onQ2IDs = record?.trackIDs
        if record != nil, let selection {
            chosenIDs = Set(SelectionResolver.resolve(selection, in: snapshot).tracksToSync.map(\.id))
        } else {
            chosenIDs = nil
        }
    }

    /// Where one song stands, or `nil` when there's no Q2 to compare with
    /// and the song can be copied.
    func placement(of id: PersistentID) -> TrackPlacement? {
        guard syncableIDs.contains(id) else {
            // A song can be on the card yet no longer copyable (its file
            // went missing after the sync, say); the card still has it.
            return onQ2IDs?.contains(id) == true ? .onQ2 : .cantSync
        }
        guard let onQ2IDs else { return nil }
        if onQ2IDs.contains(id) { return .onQ2 }
        return chosenIDs?.contains(id) == true ? .nextSync : .notChosen
    }

    /// Counts for a group's songs.
    func marks(for trackIDs: [PersistentID]) -> GroupMarks {
        var marks = GroupMarks()
        // A playlist can list the same song twice; count each song once.
        for id in Set(trackIDs) {
            marks.total += 1
            let syncable = syncableIDs.contains(id)
            if syncable { marks.syncable += 1 }
            if onQ2IDs?.contains(id) == true {
                marks.onQ2 += 1
            } else if syncable, chosenIDs?.contains(id) == true {
                marks.nextSync += 1
            }
        }
        return marks
    }
}
