//
//  PodcastSelection.swift
//  Q2-Sync › Core › Models
//
//  PURPOSE
//  What a Q2's Podcasts tab is set to (issue #20): "Sync podcasts onto
//  [Q2]" on or off, all shows or only the ticked ones, and "Unplayed
//  only".
//
//  HOW IT FITS
//  Saved per Q2 in `KnownDevice.podcasts` and part of `DeviceSyncSettings`,
//  so Revert and Apply cover it. Shows are remembered by `PodcastShow.id`.
//  Every downloaded episode of a chosen show is copied, except video and
//  protected ones (never) and, with "Unplayed only", played ones. An
//  episode in progress still counts as unplayed, so it doesn't vanish
//  from the card halfway through.
//

import Foundation

/// The Podcasts tab's settings for one Q2.
struct PodcastSelection: Codable, Hashable, Sendable {

    /// "Sync podcasts onto [Q2]". Off by default.
    var isEnabled = false

    /// `true`: all shows (shows added later come too).
    /// `false`: only the shows in `showIDs`.
    var includesAll = true

    /// The ticked shows when `includesAll` is off. Kept while "All" is on,
    /// so switching back to "Selected" brings the ticks back.
    var showIDs: Set<String> = []

    /// "Unplayed only": skip episodes the Podcasts app has marked played.
    var unplayedOnly = false

    init(isEnabled: Bool = false, includesAll: Bool = true, showIDs: Set<String> = [],
         unplayedOnly: Bool = false) {
        self.isEnabled = isEnabled
        self.includesAll = includesAll
        self.showIDs = showIDs
        self.unplayedOnly = unplayedOnly
    }

    /// `true` if the show's tick box shows ticked.
    func isTicked(_ show: PodcastShow) -> Bool {
        includesAll || showIDs.contains(show.id)
    }

    /// `true` if the episode is copied to the Q2.
    func includes(_ episode: PodcastEpisode) -> Bool {
        isEnabled && episode.canSync && (includesAll || showIDs.contains(episode.showID))
            && !(unplayedOnly && episode.playState == .played)
    }

    /// The episodes to copy, from every show, in the order given.
    func episodes(from shows: [PodcastShow]) -> [PodcastEpisode] {
        shows.flatMap(\.episodes).filter(includes)
    }

    /// Ticks or unticks shows under "Selected". Ignored under "All".
    mutating func setTicked(_ ticked: Bool, ids: Set<String>) {
        guard !includesAll else { return }
        if ticked { showIDs.formUnion(ids) } else { showIDs.subtract(ids) }
    }

    // Missing keys decode to their defaults, so later additions don't
    // break settings saved by this version.
    private enum CodingKeys: String, CodingKey { case isEnabled, includesAll, showIDs, unplayedOnly }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        includesAll = try c.decodeIfPresent(Bool.self, forKey: .includesAll) ?? true
        showIDs = try c.decodeIfPresent(Set<String>.self, forKey: .showIDs) ?? []
        unplayedOnly = try c.decodeIfPresent(Bool.self, forKey: .unplayedOnly) ?? false
    }
}

extension PodcastSelection: ContentSyncChoice {

    /// `true` if podcasts are off, or on with "Selected" and no ticks.
    var choosesNothing: Bool { !isEnabled || (!includesAll && showIDs.isEmpty) }
}
