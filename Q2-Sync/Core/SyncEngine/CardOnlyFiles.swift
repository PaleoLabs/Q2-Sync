//
//  CardOnlyFiles.swift
//  Q2-Sync › Core › SyncEngine
//
//  PURPOSE
//  Finds music on the card that isn't part of what you sync from the Mac
//  ("card-only" music), so you can decide, item by item, what happens to
//  each one. Nothing is ever deleted automatically.
//
//  TWO KINDS OF CARD-ONLY MUSIC
//  1. Unmanaged files: audio files Q2 Sync didn't put there (copied by
//     hand, from another app, an old sync tool…), anywhere on the card
//     except reserved items, the app's own `.q2sync` folder and the
//     playlist folder.
//  2. Songs Q2 Sync synced earlier whose track has since disappeared from
//     your Mac library. The card might hold the only copy, so they're
//     offered here (with "Move to Mac") rather than as plain removals.
//
//  THE CHOICES
//  Leave (the default) · Move to Mac (copy to Downloads › Q2 Recovered,
//  then delete from the card once the copy is checked) · Delete.
//
//  HOW IT FITS
//      card scan + manifest ──▶ CardOnlyFinder ──▶ [CardOnlyItem]
//      AudioTagReader fills in tags ──▶ preview lists them with a choice each
//      SyncExecutor applies the choices (copy-backs through RecoveryCopier)
//

import AVFoundation
import Foundation

/// What to do with one card-only file.
enum CardOnlyAction: String, Sendable, CaseIterable, Identifiable, Codable {
    case leave
    /// Copy to the Mac, then delete from the card if the copy worked.
    case moveToMac
    case delete

    var id: String { rawValue }

    /// Label for menus.
    var title: String {
        switch self {
        case .leave:       return "Leave on Card"
        case .moveToMac:   return "Move to Mac"
        case .delete:      return "Delete from Card"
        }
    }

    /// Label for a choice that covers a whole group.
    var allTitle: String {
        switch self {
        case .leave:       return "Leave All on Card"
        case .moveToMac:   return "Move All to Mac"
        case .delete:      return "Delete All from Card"
        }
    }

    /// `true` if the file leaves the card's music.
    var removesFromCard: Bool { self == .moveToMac || self == .delete }

}

/// The three kinds of card-only music the preview lists separately, each
/// with its own choice.
enum CardOnlyGroup: String, Sendable, CaseIterable, Identifiable, Hashable {
    /// Synced earlier; its track has left the library.
    case removedFromLibrary
    /// Not put there by Q2 Sync.
    case unmanaged
    /// A copy of a song the library has as a local file (either kind).
    case inLibrary

    var id: String { rawValue }

    /// The group an item belongs in. "Already in your library" wins, since
    /// that's what decides the sensible choice.
    init(_ item: CardOnlyItem) {
        if item.isInLibrary { self = .inLibrary }
        else if item.origin == .unmanaged { self = .unmanaged }
        else { self = .removedFromLibrary }
    }

    var title: String {
        switch self {
        case .removedFromLibrary: return "On Card Only"
        case .unmanaged:          return "Not Put There by Q2 Sync"
        case .inLibrary:          return "Already in Your Library"
        }
    }

    var explanation: String {
        switch self {
        case .removedFromLibrary: return "Synced earlier. The card may have the only copy."
        case .unmanaged:          return "Copied by hand or by another app."
        case .inLibrary:          return "Copies of songs your library has, so there's nothing to move to your Mac. Delete frees their space."
        }
    }

    /// The line in the preview's choice box, e.g. "67 songs on the card
    /// are no longer in your library."
    func summary(count: Int) -> String {
        let songs = count == 1 ? "1 song on the card" : "\(count.formatted()) songs on the card"
        let verb = count == 1 ? "is" : "are"
        switch self {
        case .removedFromLibrary: return "\(songs) \(verb) no longer in your library."
        case .unmanaged:          return "\(songs) \(count == 1 ? "wasn't" : "weren't") put there by Q2 Sync."
        case .inLibrary:          return "\(songs) \(verb) extra copies of songs in your library."
        }
    }

    /// The choices that make sense here: copying a song your library
    /// already has does nothing, so Move to Mac isn't offered.
    var actions: [CardOnlyAction] {
        self == .inLibrary ? [.leave, .delete] : CardOnlyAction.allCases
    }
}

/// The user's card-only choices: one per group, which either covers every
/// file in the group or hands over to per-file choices.
struct CardOnlyChoices: Sendable, Equatable {

    /// A group's choice.
    enum GroupChoice: Sendable, Hashable {
        /// Every file in the group gets this action.
        case all(CardOnlyAction)
        /// Each file has its own action.
        case individually
    }

    /// Groups not listed are "Leave All on Card".
    var groups: [CardOnlyGroup: GroupChoice] = [:]
    /// Per-file choices. Kept while a group covers everything, so they come
    /// back when the group returns to "Choose Individually".
    var perFile: [CardPath: CardOnlyAction] = [:]

    func choice(for group: CardOnlyGroup) -> GroupChoice { groups[group] ?? .all(.leave) }

    /// What happens to one file.
    func action(for item: CardOnlyItem) -> CardOnlyAction {
        let group = CardOnlyGroup(item)
        switch choice(for: group) {
        case .all(let action): return action
        case .individually:
            let action = perFile[item.path] ?? .leave
            return group.actions.contains(action) ? action : .leave
        }
    }

    /// Every item's action, for `SyncOptions.cardOnlyActions` (Leave is
    /// left out, as "missing" means leave).
    func actions(for items: [CardOnlyItem]) -> [CardPath: CardOnlyAction] {
        var result: [CardPath: CardOnlyAction] = [:]
        for item in items {
            let action = action(for: item)
            if action != .leave { result[item.path] = action }
        }
        return result
    }

    /// Changes a group's choice. Switching to "Choose Individually" starts
    /// files that have no choice of their own on the group's previous one.
    mutating func setChoice(_ choice: GroupChoice, for group: CardOnlyGroup, items: [CardOnlyItem]) {
        if choice == .individually, case .all(let previous) = self.choice(for: group) {
            for item in items where CardOnlyGroup(item) == group && perFile[item.path] == nil {
                perFile[item.path] = previous
            }
        }
        groups[group] = choice
    }
}

/// One card-only music file.
struct CardOnlyItem: Sendable, Hashable, Identifiable {

    /// Where it came from.
    enum Origin: Sendable, Hashable {
        /// Not put there by Q2 Sync.
        case unmanaged
        /// Synced by Q2 Sync earlier; its track is no longer in your library.
        case removedFromLibrary(trackID: PersistentID)
    }

    let path: CardPath
    let size: UInt64
    let origin: Origin
    /// Tags, if they could be read (or from the manifest for synced songs).
    var title: String?
    var artist: String?
    var album: String?
    var durationSeconds: Double?
    /// `true` if your library has this song as a local file already
    /// (matched by title, artist and length). Copying it back is skipped.
    var isInLibrary = false

    var id: CardPath { path }

    /// e.g. "Adele — Hello", or the file name when untagged.
    var displayName: String {
        guard let title else { return (path as NSString).lastPathComponent }
        return [artist, title].compactMap { $0 }.joined(separator: " — ")
    }
}

/// Card-only files from one album, for the preview's album rows.
struct CardOnlyAlbum: Sendable, Identifiable {
    /// Folder and album name, so two "Greatest Hits" stay apart.
    let id: String
    /// The album tag, or the folder name for untagged files.
    let title: String
    /// Set when every song has the same artist.
    let artist: String?
    let items: [CardOnlyItem]

    var size: UInt64 { items.reduce(0) { $0 + $1.size } }

    /// e.g. "The SteelDrivers — Hammer Down".
    var displayName: String { [artist, title].compactMap { $0 }.joined(separator: " — ") }

    /// Groups items by folder and album tag, keeping their order.
    static func group(_ items: [CardOnlyItem]) -> [CardOnlyAlbum] {
        var order: [String] = []
        var byKey: [String: [CardOnlyItem]] = [:]
        for item in items {
            let folder = (item.path as NSString).deletingLastPathComponent
            let key = "\(folder.lowercased())|\(item.album?.lowercased() ?? "")"
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(item)
        }
        return order.map { key in
            let songs = byKey[key] ?? []
            let first = songs[0]
            let folder = (first.path as NSString).deletingLastPathComponent
            let title = first.album ?? (folder.isEmpty ? "Unknown Album" : (folder as NSString).lastPathComponent)
            let artists = Set(songs.map { $0.artist ?? "" })
            let artist = artists.count == 1 ? first.artist : nil
            return CardOnlyAlbum(id: key, title: title, artist: artist, items: songs)
        }
    }
}

/// Finds card-only music.
enum CardOnlyFinder {

    /// Lists card-only files.
    ///
    /// - Parameters:
    ///   - allCardFiles: Every non-reserved file on the card (whole-card scan).
    ///   - manifest: Songs Q2 Sync manages.
    ///   - orphanedEntries: Managed songs whose track left the library.
    ///   - adoptedPaths: Files this sync's plan adopts (library songs already
    ///     on the card but missing from the manifest, e.g. after a sync was
    ///     interrupted before it saved the manifest). They're about to be
    ///     managed, so they're not card-only, and must never be offered for
    ///     trashing or deleting.
    ///   - profile: Folder names.
    /// - Returns: Items sorted by path.
    static func find(allCardFiles: [String: CardFile], manifest: SyncManifest,
                     orphanedEntries: [RemoveOperation], adoptedPaths: [CardPath] = [],
                     profile: DeviceProfile) -> [CardOnlyItem] {
        let managedKeys = Set(manifest.entries.values.map { CardLayout.caseKey($0.path) })
            .union(adoptedPaths.map(CardLayout.caseKey))
        let skippedTopFolders: Set<String> = [profile.appStateFolderName.lowercased(),
                                              profile.playlistFolderName.lowercased()]
        var items: [CardOnlyItem] = []

        // 1. Unmanaged audio files.
        for (key, file) in allCardFiles where !managedKeys.contains(key) {
            let top = file.path.split(separator: "/").first.map { String($0).lowercased() } ?? ""
            guard !skippedTopFolders.contains(top) else { continue }
            let ext = (file.path as NSString).pathExtension.lowercased()
            guard CardScanner.audioExtensions.contains(ext) else { continue }
            items.append(CardOnlyItem(path: file.path, size: file.size, origin: .unmanaged))
        }

        // 2. Synced songs that left the library (only if still on the card).
        for orphan in orphanedEntries where allCardFiles[CardLayout.caseKey(orphan.entry.path)] != nil {
            items.append(CardOnlyItem(path: orphan.entry.path, size: orphan.entry.cardSize,
                                      origin: .removedFromLibrary(trackID: orphan.trackID),
                                      title: orphan.entry.title, artist: orphan.entry.artist,
                                      album: orphan.entry.album))
        }
        return items.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Marks items your library already has as LOCAL files (same title and
    /// artist, ignoring case, and length within 2 seconds). A cloud-only
    /// match doesn't count: then the card copy may be the only file.
    static func markLibraryMatches(_ items: inout [CardOnlyItem], snapshot: LibrarySnapshot) {
        var index: [String: [Track]] = [:]
        for track in snapshot.tracks where track.isCopyable {
            index[matchKey(title: track.title, artist: track.artist), default: []].append(track)
        }
        for i in items.indices {
            guard let title = items[i].title,
                  let candidates = index[matchKey(title: title, artist: items[i].artist)] else { continue }
            if let duration = items[i].durationSeconds {
                items[i].isInLibrary = candidates.contains { abs($0.durationSeconds - duration) <= 2 }
            } else {
                items[i].isInLibrary = false // Without a length we can't be sure.
            }
        }
    }

    /// Turns new-song copies into adoptions of the same song already on the
    /// card, for music copied there by hand (in Finder, say).
    ///
    /// A card-only file counts as the same song when it's in the music
    /// folder (not in a hidden folder), its title and artist match (ignoring
    /// case), its length is within 2 seconds, and its size equals the Mac
    /// file's exactly. Then, instead of copying the song again, the plan
    /// adopts that file and moves it to Q2 Sync's path for it, and it's no
    /// longer card-only. Other matches stay card-only (marked "already in
    /// your library"), for the user to trash or delete.
    ///
    /// Call after `fillTags` and `markLibraryMatches`, with the plan's
    /// `cardOnly` filled in.
    ///
    /// - Parameters:
    ///   - plan: The plan to adjust.
    ///   - musicFolderName: The card's music folder, e.g. "Music".
    /// - Returns: How many copies were turned into adoptions.
    @discardableResult
    static func adoptIdenticalCopies(in plan: inout SyncPlan, musicFolderName: String) -> Int {
        let musicFolder = musicFolderName.lowercased()
        // Candidates by title|artist; each is used at most once.
        var candidates: [String: [CardOnlyItem]] = [:]
        for item in plan.cardOnly where item.origin == .unmanaged && item.isInLibrary {
            let parts = item.path.split(separator: "/").map(String.init)
            guard parts.count >= 2, parts[0].lowercased() == musicFolder,
                  !parts.contains(where: { $0.hasPrefix(".") }),
                  let title = item.title, item.durationSeconds != nil else { continue }
            candidates[matchKey(title: title, artist: item.artist), default: []].append(item)
        }
        guard !candidates.isEmpty else { return 0 }

        var adopted = Set<CardPath>()
        var keptCopies: [CopyOperation] = []
        for copy in plan.copies {
            let track = copy.track
            let key = matchKey(title: track.title, artist: track.artist)
            guard copy.kind == .add,
                  let index = candidates[key]?.firstIndex(where: { item in
                      item.size == track.fileSize
                          && abs((item.durationSeconds ?? -10) - track.durationSeconds) <= 2
                  }),
                  let item = candidates[key]?.remove(at: index) else {
                keptCopies.append(copy)
                continue
            }
            plan.adoptions.append(AdoptOperation(track: track, path: item.path, size: item.size))
            if CardLayout.caseKey(item.path) != CardLayout.caseKey(copy.destination) {
                plan.moves.append(MoveOperation(track: track, from: item.path, to: copy.destination))
            }
            adopted.insert(item.path)
        }
        plan.copies = keptCopies
        plan.cardOnly.removeAll { adopted.contains($0.path) }
        return adopted.count
    }

    private static func matchKey(title: String, artist: String?) -> String {
        "\(title.lowercased())|\((artist ?? "").lowercased())"
    }
}

/// Reads basic tags from an audio file (read-only), using AVFoundation.
enum AudioTagReader {

    /// Fills in title, artist, album and length for items that lack them.
    ///
    /// - Parameters:
    ///   - items: Items to complete.
    ///   - cardRoot: The card root, to build file URLs.
    /// - Side effects: Opens each file for reading only.
    static func fillTags(_ items: inout [CardOnlyItem], cardRoot: URL) async {
        for i in items.indices {
            let url = cardRoot.appending(path: items[i].path)
            let asset = AVURLAsset(url: url)
            // `try?` turns any failure (unreadable or unsupported file) into
            // nil, so one odd file can't stop the scan.
            guard let (metadata, duration) = try? await asset.load(.commonMetadata, .duration) else { continue }
            items[i].durationSeconds = duration.seconds.isFinite ? duration.seconds : items[i].durationSeconds
            if items[i].title == nil {
                items[i].title = await string(.commonIdentifierTitle, in: metadata)
                items[i].artist = await string(.commonIdentifierArtist, in: metadata)
                items[i].album = await string(.commonIdentifierAlbumName, in: metadata)
            }
        }
    }

    /// The first string value for a metadata identifier, if any.
    private static func string(_ identifier: AVMetadataIdentifier, in metadata: [AVMetadataItem]) async -> String? {
        let matches = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier)
        guard let item = matches.first else { return nil }
        return (try? await item.load(.stringValue))?.nonEmpty
    }
}
