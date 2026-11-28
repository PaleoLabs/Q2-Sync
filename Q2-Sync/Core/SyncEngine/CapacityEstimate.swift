//
//  CapacityEstimate.swift
//  Q2-Sync › Core › SyncEngine
//
//  PURPOSE
//  Works out the numbers for the Finder-style capacity bar: how much of the
//  card is Q2 Sync's music, other files, music the current selection would
//  add, and free space, plus whether the selection fits.
//
//  HOW IT FITS
//  The device page recomputes this whenever the selection changes. It's a
//  quick estimate from the manifest and the library's file sizes (no card
//  scan), so it can update instantly as you tick boxes. The full sync
//  preview later does the exact check before anything is copied.
//
//  THE MATHS
//    used          = total − free
//    music         = sizes of songs Q2 Sync has on the card (manifest)
//    other         = used − music   (firmware files, card-only music, …)
//    toAdd         = selected songs not on the card yet (library sizes)
//    deselected    = Q2 Sync songs on the card that aren't selected; they
//                    stay unless you choose to remove them in the preview
//    free after    = free − toAdd            (without removals)
//                  = free − toAdd + deselected (with removals)
//  The app always keeps `SyncSafety.reservedFreeBytes` free.
//
//  WHEN THE NUMBERS CAN'T BE TRUSTED
//  • Card unreadable (no access): Q2 Sync can't see its own songs, so all
//    of `used` is shown as plain used space and nothing as "to add";
//    otherwise every song would count twice (once as other, once to add).
//  • Music copied onto the card by hand sits in `other`, and the same songs
//    count in `toAdd`; the sync adopts library matches instead of copying
//    them. The bar flags this (`mayIncludeOwnMusic`); the sync preview
//    scans the card and checks exactly.
//

import Foundation

/// Capacity numbers for one card and selection.
struct CapacityEstimate: Sendable, Equatable {

    /// Whether the selection fits.
    enum Fit: Sendable, Equatable {
        /// Fits, keeping the reserve free.
        case fits
        /// Fits only if songs you deselected are removed in the preview.
        case fitsIfRemovingDeselected
        /// Doesn't fit even then; `shortBy` bytes too many.
        case doesNotFit(shortBy: Int64)
    }

    var totalBytes: Int64
    var freeBytes: Int64
    /// Q2 Sync's songs on the card that are still selected.
    var selectedMusicBytes: Int64
    /// Q2 Sync's songs on the card that are no longer selected.
    var deselectedMusicBytes: Int64
    /// Audiobooks Q2 Sync has on the card that are still chosen.
    var audiobookBytes: Int64 = 0
    /// Podcast episodes Q2 Sync has on the card that are still synced.
    var podcastBytes: Int64 = 0
    /// Everything else on the card.
    var otherBytes: Int64
    /// Selected songs not on the card yet.
    var toAddBytes: Int64
    /// The verdict.
    var fit: Fit
    /// `false` if Q2 Sync can't read the card (no access): then only
    /// `otherBytes` (all used space) and free space mean anything.
    var isCardReadable: Bool = true

    /// "Other" this big may hold music copied onto the card by hand.
    static let ownMusicHintBytes: Int64 = 1_000_000_000

    /// `true` if the card holds a lot that Q2 Sync didn't add while the
    /// selection adds songs: some may already be there (copied by hand),
    /// matched at the sync, so less may be copied than `toAddBytes`.
    var mayIncludeOwnMusic: Bool {
        isCardReadable && otherBytes >= Self.ownMusicHintBytes && toAddBytes > 0
    }

    /// Free space after the sync if deselected songs are kept.
    var freeAfterBytes: Int64 { freeBytes - toAddBytes }

    /// Computes the estimate.
    ///
    /// - Parameters:
    ///   - totalBytes: Card size.
    ///   - freeBytes: Free space now.
    ///   - manifest: Songs Q2 Sync has on the card (`nil` if unknown).
    ///   - selection: The resolved selection, or `nil` if the library
    ///     hasn't been read yet (then nothing is "to add").
    ///   - reserve: Space always left free.
    ///   - cardReadable: `false` if Q2 Sync can't read the card (no
    ///     access): all used space is shown as such, nothing to add.
    ///   - audiobooks: Apple Books' audiobooks and the Q2's Audiobooks
    ///     settings, or `nil` if not read (then audiobooks on the card
    ///     count as chosen, and nothing as to add). Audiobooks no longer
    ///     chosen count with deselected songs; new ones with songs to add.
    ///   - podcasts: The downloaded podcasts and the Q2's Podcasts
    ///     settings, or `nil` if not read; counted the same way as
    ///     audiobooks. An episode a q2-podcasts copy already covers still
    ///     counts as to add (a slight overestimate).
    /// - Returns: The estimate.
    static func compute(totalBytes: Int64, freeBytes: Int64, manifest: SyncManifest?,
                        selection: ResolvedSelection?,
                        reserve: Int64 = SyncSafety.reservedFreeBytes,
                        cardReadable: Bool = true,
                        audiobooks: (books: [Audiobook], selection: AudiobookSelection)? = nil,
                        podcasts: (shows: [PodcastShow], selection: PodcastSelection)? = nil) -> CapacityEstimate {
        guard cardReadable else {
            return CapacityEstimate(totalBytes: totalBytes, freeBytes: freeBytes,
                                    selectedMusicBytes: 0, deselectedMusicBytes: 0,
                                    otherBytes: max(0, totalBytes - freeBytes), toAddBytes: 0,
                                    fit: .fits, isCardReadable: false)
        }
        let entries = manifest?.entries ?? [:]
        let selectedIDs = Set(selection.map { ($0.tracksToSync + $0.skippedTracks).map(\.id) } ?? [])

        var selectedMusic: Int64 = 0
        var deselectedMusic: Int64 = 0
        for (id, entry) in entries {
            // Without a selection, treat everything on the card as selected.
            if selection == nil || selectedIDs.contains(id) {
                selectedMusic += Int64(entry.cardSize)
            } else {
                deselectedMusic += Int64(entry.cardSize)
            }
        }

        var toAdd: Int64 = 0
        for track in selection?.tracksToSync ?? [] {
            if let entry = entries[track.id] {
                // Re-copied if changed: count only any growth.
                if track.fileSize != entry.sourceSize {
                    toAdd += max(0, Int64(track.fileSize) - Int64(entry.cardSize))
                }
            } else {
                toAdd += Int64(track.fileSize)
            }
        }

        // Audiobooks (see AudiobookSync.swift): by book, from the manifest.
        var audiobookOnCard: Int64 = 0
        let records = manifest?.audiobooks ?? [:]
        let keptBooks: Set<String>? = audiobooks.map { books, settings in
            Set(books.filter { settings.isEnabled && (settings.includesAll || settings.bookIDs.contains($0.id)) }.map(\.id))
        }
        for (id, record) in records {
            let bytes = record.files.reduce(Int64(0)) { $0 + Int64($1.cardSize) }
            if keptBooks?.contains(id) ?? true { audiobookOnCard += bytes } else { deselectedMusic += bytes }
        }
        if let (books, settings) = audiobooks {
            for book in settings.books(from: books) where records[book.id] == nil {
                toAdd += Int64(book.totalSize)
            }
        }

        // Podcasts (see PodcastSync.swift): by episode, from the manifest.
        // Kept: still synced, or in a chosen show but not copyable now.
        var podcastOnCard: Int64 = 0
        let episodeRecords = manifest?.podcasts ?? [:]
        let keptEpisodes: Set<String>? = podcasts.map { shows, settings in
            Set(shows.flatMap(\.episodes).filter {
                settings.includes($0)
                    || (settings.isEnabled && !$0.canSync && (settings.includesAll || settings.showIDs.contains($0.showID)))
            }.map(\.id))
        }
        for (id, record) in episodeRecords {
            if keptEpisodes?.contains(id) ?? true { podcastOnCard += Int64(record.cardSize) }
            else { deselectedMusic += Int64(record.cardSize) }
        }
        if let (shows, settings) = podcasts {
            for episode in settings.episodes(from: shows) where episodeRecords[episode.id] == nil {
                toAdd += Int64(episode.fileSize)
            }
        }

        let used = max(0, totalBytes - freeBytes)
        let other = max(0, used - selectedMusic - deselectedMusic - audiobookOnCard - podcastOnCard)

        let fit: Fit
        if freeBytes - toAdd >= reserve {
            fit = .fits
        } else if freeBytes - toAdd + deselectedMusic >= reserve {
            fit = .fitsIfRemovingDeselected
        } else {
            fit = .doesNotFit(shortBy: reserve - (freeBytes - toAdd + deselectedMusic))
        }

        return CapacityEstimate(totalBytes: totalBytes, freeBytes: freeBytes,
                                selectedMusicBytes: selectedMusic, deselectedMusicBytes: deselectedMusic,
                                audiobookBytes: audiobookOnCard, podcastBytes: podcastOnCard,
                                otherBytes: other, toAddBytes: toAdd, fit: fit)
    }
}
