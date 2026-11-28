//
//  Podcast.swift
//  Q2-Sync › Core › Models
//
//  PURPOSE
//  Our own, read-only description of the podcast episodes the Podcasts
//  app has downloaded on this Mac (issue #20): each `PodcastEpisode` is
//  one downloaded file, grouped into `PodcastShow`s.
//
//  HOW IT FITS
//  `ApplePodcastsSource` reads the Podcasts app's cache folder and its
//  database and turns them into these values. The Podcasts tab, the sync
//  planner and the capacity bar work only with them. Plain `Sendable`
//  values: nothing here can change the Podcasts app.
//
//  Only *downloaded* episodes are listed: the Podcasts database knows
//  thousands of episodes, but the cache files decide what can sync.
//

import Foundation

/// Where an episode is in playing, from the Podcasts app's `ZPLAYSTATE`
/// (checked on macOS 27.2: playing to the end gives 0, partway gives 1).
enum PodcastPlayState: String, Codable, Sendable, Hashable {
    case played
    case inProgress
    case unplayed

    /// The state for a `ZPLAYSTATE` value. Anything unknown counts as
    /// unplayed, so it still syncs under "Unplayed only".
    init(databaseValue: Int?) {
        switch databaseValue {
        case 0: self = .played
        case 1: self = .inProgress
        default: self = .unplayed
        }
    }
}

/// Audio or video, from the episode file's type. Video isn't synced yet
/// (#69); video episodes are listed dimmed.
enum PodcastEpisodeKind: String, Codable, Sendable, Hashable {
    case audio
    case video

    /// File types that are video (`mp4` included: Podcasts uses it for
    /// video, and an audio-only `.mp4` is rare).
    static let videoExtensions: Set<String> = ["mp4", "m4v", "mov"]

    /// The kind for a file extension. `nil` if it's neither an audio type
    /// the card plays (`CardScanner.audioExtensions`) nor a video type.
    init?(fileExtension: String) {
        let ext = fileExtension.lowercased()
        if CardScanner.audioExtensions.contains(ext) {
            self = .audio
        } else if Self.videoExtensions.contains(ext) {
            self = .video
        } else {
            return nil
        }
    }
}

/// One downloaded episode.
struct PodcastEpisode: Codable, Hashable, Identifiable, Sendable {

    /// The Podcasts app's episode UUID (`ZMTEPISODE.ZUUID`), which is also
    /// the cache file's name. What the manifest remembers.
    let id: String

    /// The show's UUID (`ZMTPODCAST.ZUUID`), what a Q2's selection remembers.
    let showID: String

    /// The show's title.
    let showTitle: String

    /// The episode's title. Never empty: falls back to "Episode".
    let title: String

    /// When the episode was published, if the database has it.
    let published: Date?

    /// The downloaded file, inside the Podcasts folder. Only ever read.
    let fileURL: URL

    /// The file's size on disk, in bytes.
    let fileSize: UInt64

    let kind: PodcastEpisodeKind
    let playState: PodcastPlayState

    /// `true` for protected subscription episodes (they have a DRM key).
    let isProtected: Bool

    /// The file's extension, e.g. `mp3`.
    var fileExtension: String { fileURL.pathExtension }

    /// `true` if it can be copied to the card: audio and not protected.
    var canSync: Bool { kind == .audio && !isProtected }

    /// Why it can't be copied, for the dimmed row; `nil` if it can.
    var unsyncableReason: String? {
        if isProtected { return "Protected episodes can't be copied." }
        if kind == .video { return "Video podcasts aren't synced yet." }
        return nil
    }
}

/// A show with its downloaded episodes.
struct PodcastShow: Codable, Hashable, Identifiable, Sendable {

    /// `ZMTPODCAST.ZUUID`.
    let id: String

    /// The show's title. Never empty: falls back to "Podcast".
    let title: String

    /// The show's author, if the database has one.
    let author: String?

    /// Downloaded episodes, newest first.
    let episodes: [PodcastEpisode]

    /// Total size of the downloaded episodes, in bytes.
    var totalSize: UInt64 { episodes.reduce(0) { $0 + $1.fileSize } }
}

/// The Podcasts tab's search field.
enum PodcastSearch {

    /// The shows whose title or author contains the text, or that have an
    /// episode whose title does (those shows keep only the matching
    /// episodes). Ignores case and accents; blank text matches everything.
    ///
    /// - Parameters:
    ///   - shows: The shows to search.
    ///   - text: What was typed.
    /// - Returns: The matching shows, in the order given.
    static func filter(_ shows: [PodcastShow], matching text: String) -> [PodcastShow] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return shows }
        return shows.compactMap { show in
            if show.title.localizedStandardContains(query) || (show.author?.localizedStandardContains(query) ?? false) {
                return show
            }
            let episodes = show.episodes.filter { $0.title.localizedStandardContains(query) }
            return episodes.isEmpty ? nil
                : PodcastShow(id: show.id, title: show.title, author: show.author, episodes: episodes)
        }
    }
}
