//
//  PodcastMarks.swift
//  Q2-Sync › Core › Models
//
//  PURPOSE
//  Where each downloaded episode stands relative to a Q2, for the
//  sidebar's Podcasts › Episodes browser: on the Q2, copied at the next
//  sync, not chosen, or can't sync. The podcast counterpart of
//  `AudiobookMarks`. Also says when the sidebar's Podcasts section shows
//  (#70).
//
//  HOW IT FITS
//  Built by `PodcastBrowserView` from the Podcasts app's downloads, the
//  Mac-side record of the card (`CardContentsRecord.podcastEpisodeIDs`)
//  and the Q2's saved podcast settings. Read-only: nothing here plans a
//  sync.
//

import Foundation

/// Episode marks for the Episodes browser.
struct PodcastMarks: Sendable, Equatable {

    /// Episodes on the Q2, or `nil` when there's no record of its episodes
    /// (no Q2 read yet, or a record saved before podcasts were recorded).
    let onQ2IDs: Set<String>?

    /// The Q2's saved podcast settings, or `nil` without a Q2.
    let selection: PodcastSelection?

    /// `true` when there's a Q2's episodes to compare with.
    var hasQ2: Bool { onQ2IDs != nil }

    /// Builds the marks.
    ///
    /// - Parameters:
    ///   - record: The Q2's last known contents, if any.
    ///   - selection: Its saved podcast settings, if any.
    init(record: CardContentsRecord?, selection: PodcastSelection?) {
        onQ2IDs = record?.podcastEpisodeIDs
        self.selection = onQ2IDs == nil ? nil : selection
    }

    /// Where one episode stands, or `nil` when there's no Q2 to compare
    /// with and the episode can be copied.
    func placement(of episode: PodcastEpisode) -> TrackPlacement? {
        if onQ2IDs?.contains(episode.id) == true { return .onQ2 }
        guard episode.canSync else { return .cantSync }
        guard onQ2IDs != nil else { return nil }
        return selection?.includes(episode) == true ? .nextSync : .notChosen
    }
}

extension Sequence where Element == KnownDevice {

    /// `true` when any of these Q2s syncs podcasts. The sidebar shows its
    /// Podcasts section then, like Audiobooks (decided on #70).
    var anySyncsPodcasts: Bool {
        contains { $0.effectivePodcasts.isEnabled }
    }
}
