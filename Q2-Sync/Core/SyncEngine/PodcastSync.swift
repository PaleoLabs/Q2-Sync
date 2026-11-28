//
//  PodcastSync.swift
//  Q2-Sync › Core › SyncEngine
//
//  PURPOSE
//  Plans the podcast part of a sync (issue #20): which downloaded episodes
//  to copy to the card, which are already there, and which Q2 Sync copied
//  earlier but are no longer wanted.
//
//  ON THE CARD (Q2 Pod only)
//      Podcasts/<show title>/<YYYY-MM-DD> - <episode title>.<ext>
//      e.g.  Podcasts/The Daily/2024-10-07 - The Election.mp3
//  `Podcasts/` is Q2 Pod's Library › Podcasts: episodes resume and stay
//  out of the music library. The names match the q2-podcasts card app,
//  so an episode it already downloaded isn't copied a second time. Files
//  are copied unchanged. The date is the publish date in this Mac's time
//  zone; an undated episode is just `<episode title>.<ext>`.
//
//  SAFETY
//  • `Podcasts/` is a reserved folder; `PathGuard` lets Q2 Sync change
//    only `Podcasts/<show>/<audio file>` there, and only on Q2 Pod.
//  • Q2 Sync records every episode it copies in the manifest
//    (`SyncManifest.podcasts`) and only ever replaces or removes files
//    recorded there. A show folder may also hold files from q2-podcasts or
//    the user: they're never overwritten or removed. A file already at an
//    episode's name counts as that episode being on the card.
//  • A recorded episode keeps its path, even if its title changes.
//  • Removing episodes is a removal like a song's: only when the user
//    ticks "remove" in the review sheet, never in an automatic sync.
//  • An empty list from the Podcasts app is trusted (with Apple's default
//    "Remove Played Downloads", every download can go). If the Podcasts
//    app can't be read, the caller doesn't plan podcasts at all.
//
//  HOW IT FITS
//  `SyncCoordinator` scans `Podcasts/`, calls `PodcastPlanner.plan` and
//  stores the result in `SyncPlan.podcasts`; `SyncExecutor` applies it.
//

import Foundation

// MARK: - Manifest record

/// An episode Q2 Sync put on the card.
struct PodcastEpisodeRecord: Codable, Sendable, Hashable {
    /// Its file, e.g. `Podcasts/The Daily/2024-10-07 - The Election.mp3`.
    var path: CardPath
    /// The show's id and title when copied.
    var showID: String
    var showTitle: String
    /// The episode's title when copied (names it in reports after its
    /// download is gone from the Mac).
    var title: String
    /// The Mac file's size when copied.
    var sourceSize: UInt64
    /// The card file's size after copying.
    var cardSize: UInt64
    var syncedAt: Date

    /// The show's folder on the card.
    var folder: CardPath {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[..<slash])
    }
}

// MARK: - Plan

/// Copying one episode to the card.
struct PodcastCopy: Sendable, Hashable, Identifiable {
    enum Kind: String, Sendable { case add, update }
    let kind: Kind
    let episodeID: String
    let showID: String
    let showTitle: String
    let title: String
    let source: URL
    let sourceSize: UInt64
    let destination: CardPath
    var id: CardPath { destination }
}

/// Removing one episode Q2 Sync copied earlier.
struct PodcastRemoval: Sendable, Hashable, Identifiable {

    /// Why it's no longer wanted (worded in the review sheet).
    enum Reason: String, Sendable {
        /// The Podcasts app no longer has it downloaded.
        case notDownloaded
        /// Its show isn't chosen any more.
        case showNotChosen
        /// It's been played and "Unplayed only" is on.
        case played
        /// "Sync podcasts" is off.
        case podcastsOff
    }

    let episodeID: String
    let showTitle: String
    let title: String
    let path: CardPath
    let cardSize: UInt64
    let reason: Reason
    var id: CardPath { path }
}

/// The podcast part of a sync.
struct PodcastPlan: Sendable, Equatable {
    var copies: [PodcastCopy] = []
    /// Episodes no longer wanted. All need the user's "remove" choice.
    var removals: [PodcastRemoval] = []
    /// Records whose file is gone from the card and that aren't wanted.
    var forgotten: [String] = []
    /// Wanted episodes already on the card as Q2 Sync copied them.
    var unchangedEpisodes = 0
    /// Wanted episodes whose name was already taken by a file Q2 Sync
    /// didn't put there (e.g. from q2-podcasts): counted as on the card,
    /// not copied, not recorded.
    var alreadyOnCard = 0
    /// Episodes of chosen shows that can't be copied (video, protected).
    var skipped: [PodcastEpisode] = []
    /// Set when podcasts weren't planned at all, e.g. the Podcasts app
    /// couldn't be read. Shown in the review sheet; nothing changes.
    var note: String?

    var bytesToCopy: UInt64 { copies.reduce(0) { $0 + $1.sourceSize } }
    var bytesFreedByRemovals: UInt64 { removals.reduce(0) { $0 + $1.cardSize } }
    var episodesToAdd: Int { copies.filter { $0.kind == .add }.count }
    var episodesToUpdate: Int { copies.filter { $0.kind == .update }.count }

    var isEmpty: Bool { copies.isEmpty && removals.isEmpty && forgotten.isEmpty }
}

/// Builds the podcast plan. Pure: changes nothing.
enum PodcastPlanner {

    /// - Parameters:
    ///   - shows: Every show with downloaded episodes (any kind).
    ///   - selection: The Q2's Podcasts settings.
    ///   - manifest: The card's manifest.
    ///   - card: What's in `Podcasts/` now.
    ///   - folderName: The profile's podcasts folder (`Podcasts`).
    ///   - timeZone: For the date in file names.
    static func plan(shows: [PodcastShow], selection: PodcastSelection, manifest: SyncManifest,
                     card: CardFolderListing, folderName: String,
                     timeZone: TimeZone = .current) -> PodcastPlan {
        var plan = PodcastPlan()
        let records = manifest.podcasts ?? [:]
        let all = shows.flatMap(\.episodes)
        let downloadedIDs = Set(all.map(\.id))
        // Oldest first, so " (2)" goes to the later of two same-named ones.
        let wanted = selection.episodes(from: shows).sorted { a, b in
            switch (a.published, b.published) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.id < b.id
            }
        }
        let wantedIDs = Set(wanted.map(\.id))
        plan.skipped = selection.isEnabled ? all.filter {
            !$0.canSync && (selection.includesAll || selection.showIDs.contains($0.showID))
        } : []
        let keepIDs = wantedIDs.union(plan.skipped.map(\.id))

        // Paths spoken for by Q2 Sync's own episodes, and which show owns
        // each recorded folder.
        var usedPaths = Set(records.values.map { CardLayout.caseKey($0.path) })
        var folderByShow: [String: CardPath] = [:]
        var showByFolder: [String: String] = [:]
        for (_, record) in records.sorted(by: { $0.key < $1.key }) {
            folderByShow[record.showID] = folderByShow[record.showID] ?? record.folder
            showByFolder[CardLayout.caseKey(record.folder)] = showByFolder[CardLayout.caseKey(record.folder)] ?? record.showID
        }

        for episode in wanted {
            if let record = records[episode.id] {
                let onCard = card.files[CardLayout.caseKey(record.path)]
                if let onCard, onCard.size == record.cardSize, record.sourceSize == episode.fileSize {
                    plan.unchangedEpisodes += 1
                } else {
                    plan.copies.append(copy(episode, kind: .update, to: record.path))
                }
                continue
            }
            let folder = showFolder(for: episode, folderName: folderName,
                                    folderByShow: &folderByShow, showByFolder: &showByFolder)
            let preferred = "\(folder)/\(fileName(for: episode, timeZone: timeZone))"
            let preferredKey = CardLayout.caseKey(preferred)
            if !usedPaths.contains(preferredKey), card.files[preferredKey] != nil {
                // Someone else's copy of this episode (e.g. q2-podcasts).
                plan.alreadyOnCard += 1
                usedPaths.insert(preferredKey)
                continue
            }
            var path = preferred
            var number = 2
            while usedPaths.contains(CardLayout.caseKey(path)) || card.files[CardLayout.caseKey(path)] != nil {
                path = CardLayout.variant(of: preferred, number: number)
                number += 1
            }
            usedPaths.insert(CardLayout.caseKey(path))
            plan.copies.append(copy(episode, kind: .add, to: path))
        }

        // Episodes Q2 Sync copied that are no longer wanted.
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, record) in records where !keepIDs.contains(id) {
            guard let onCard = card.files[CardLayout.caseKey(record.path)] else {
                plan.forgotten.append(id)
                continue
            }
            let reason: PodcastRemoval.Reason
            if !selection.isEnabled {
                reason = .podcastsOff
            } else if !downloadedIDs.contains(id) {
                reason = .notDownloaded
            } else if let episode = byID[id], !(selection.includesAll || selection.showIDs.contains(episode.showID)) {
                reason = .showNotChosen
            } else {
                reason = .played
            }
            plan.removals.append(PodcastRemoval(episodeID: id, showTitle: record.showTitle, title: record.title,
                                                path: record.path, cardSize: onCard.size, reason: reason))
        }
        plan.copies.sort { SortKey.compare($0.destination, $1.destination) }
        plan.removals.sort { SortKey.compare($0.path, $1.path) }
        plan.forgotten.sort()
        return plan
    }

    /// The episode's card file name: `YYYY-MM-DD - Title.ext`, sanitised.
    static func fileName(for episode: PodcastEpisode, timeZone: TimeZone = .current) -> String {
        var base = episode.title
        if let date = episode.published {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let d = calendar.dateComponents([.year, .month, .day], from: date)
            base = String(format: "%04d-%02d-%02d - ", d.year ?? 0, d.month ?? 0, d.day ?? 0) + base
        }
        return FilenameSanitizer.sanitizeFileName(base: base, fileExtension: episode.fileExtension, fallback: "Episode")
    }

    /// The show's folder: the one its recorded episodes are in, else
    /// `Podcasts/<show title>` — shared with q2-podcasts or the user, but
    /// not with another show Q2 Sync manages ("Title (2)" then).
    private static func showFolder(for episode: PodcastEpisode, folderName: String,
                                   folderByShow: inout [String: CardPath],
                                   showByFolder: inout [String: String]) -> CardPath {
        if let folder = folderByShow[episode.showID] { return folder }
        let preferred = "\(folderName)/" + FilenameSanitizer.sanitizeComponent(episode.showTitle, fallback: "Podcast")
        let otherShows = Set(showByFolder.filter { $0.value != episode.showID }.keys)
        let folder = AudiobookPlanner.freeFolder(preferred, taken: otherShows)
        folderByShow[episode.showID] = folder
        showByFolder[CardLayout.caseKey(folder)] = episode.showID
        return folder
    }

    private static func copy(_ episode: PodcastEpisode, kind: PodcastCopy.Kind, to path: CardPath) -> PodcastCopy {
        PodcastCopy(kind: kind, episodeID: episode.id, showID: episode.showID, showTitle: episode.showTitle,
                    title: episode.title, source: episode.fileURL, sourceSize: episode.fileSize, destination: path)
    }
}
