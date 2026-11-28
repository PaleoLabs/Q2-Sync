//
//  PhotoSync.swift
//  Q2-Sync › Core › SyncEngine
//
//  PURPOSE
//  Plans the photo part of a sync (issue #68): which photos to put on the
//  card and in which folder, which are already there, which to redo, and
//  which Q2 Sync copied earlier but are no longer wanted.
//
//  ON THE CARD (Q2 Pod only)
//      Photos/<YYYY-MM-DD> <name>.jpg              (in no album)
//      Photos/<Album>/<YYYY-MM-DD> <name>.jpg      (in an album)
//      e.g.  Photos/Iceland/2024-07-01 IMG_1234.jpg
//  Q2 Pod's Photos › All Photos shows the loose photos, then every album
//  folder's; each album folder is also its own album. Albums inside
//  Photos folders are flattened to one level. Every photo is a JPEG
//  (HEIC and PNG originals too), named by the day it was taken in this
//  Mac's time zone and the original's name ("Photo" if unknown).
//
//  WHICH PHOTOS GO WHERE
//  • "All photos and albums": each user album as a folder, plus every
//    photo in no user album loose in `Photos/`, so All Photos shows the
//    whole library. Hidden photos and smart albums (Favorites, Recently
//    Added, media types, Hidden) don't come.
//  • "Selected albums": each ticked album as a folder (Hidden included if
//    ticked: it's the only way hidden photos sync). Photos from
//    "Automatically include photos from" go loose in `Photos/`, unless a
//    ticked album already brings them.
//  • "Only favorites" keeps only favourites, in every folder.
//  • A photo in two albums is copied twice (exFAT has no links), and shows
//    twice in All Photos.
//  • Q2 Pod shows at most 500 photos per grid (All Photos, and each
//    album) and 200 albums. Everything is still copied; the plan warns.
//
//  SAFETY
//  • `Photos/` is a reserved folder; `PathGuard` lets Q2 Sync change only
//    `Photos/[<album>/]<.jpg/.jpeg/.png>` there, and only on Q2 Pod.
//  • Q2 Sync records every photo it copies in the manifest
//    (`SyncManifest.photos`), one record per photo per folder, and only
//    ever replaces or removes files recorded there. Files someone else
//    put in `Photos/` are never overwritten (a new photo takes a free
//    name) or removed.
//  • A recorded photo keeps its path, even if its album is renamed.
//  • Removing photos is a removal like a song's: only when the user ticks
//    "remove" in the review sheet, never in an automatic sync.
//  • If the Photos library can't be read, the caller doesn't plan photos
//    at all. Only the Photos library source exists so far: a folder
//    source plans nothing and says so.
//
//  HOW IT FITS
//  `SyncCoordinator` scans `Photos/`, calls `PhotoPlanner.plan` and stores
//  the result in `SyncPlan.photos`; `SyncExecutor` renders and writes it.
//

import Foundation

// MARK: - Manifest record

/// One photo Q2 Sync put in one card folder.
struct PhotoRecord: Codable, Sendable, Hashable {
    /// Its file, e.g. `Photos/Iceland/2024-07-01 IMG_1234.jpg`.
    var path: CardPath
    /// The photo (`PhotoAsset.id`).
    var assetID: String
    /// The album whose folder it's in, and its title when copied; `nil`
    /// for a photo loose in `Photos/`.
    var albumID: String?
    var albumTitle: String?
    /// The photo's edit date when copied: a later one redoes the copy.
    var modified: Date?
    /// Copied at full resolution (or as a screen-size copy).
    var fullResolution: Bool
    /// The card file's size after writing.
    var cardSize: UInt64
    var syncedAt: Date

    /// The manifest key: one asset can be in several folders.
    var key: String { PhotoPlanner.key(assetID: assetID, albumID: albumID) }

    /// The album's folder on the card (`Photos` for a loose photo).
    var folder: CardPath {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[..<slash])
    }
}

// MARK: - Plan

/// Writing one photo to the card.
struct PhotoCopy: Sendable, Hashable, Identifiable {

    enum Kind: String, Sendable {
        /// Not on the card yet.
        case add
        /// On the card, but edited since, missing, changed on the card, or
        /// "Include full-resolution photos" changed.
        case update
    }

    let kind: Kind
    let assetID: String
    let albumID: String?
    let albumTitle: String?
    let destination: CardPath
    let modified: Date?
    let fullResolution: Bool
    /// A guess at the card file's size, for the capacity bar.
    let estimatedSize: UInt64

    /// The manifest key for this photo in this folder.
    var key: String { PhotoPlanner.key(assetID: assetID, albumID: albumID) }
    var id: CardPath { destination }
}

/// Removing one photo Q2 Sync copied earlier.
struct PhotoRemoval: Sendable, Hashable, Identifiable {

    /// Why it's no longer wanted (worded in the review sheet).
    enum Reason: String, Sendable {
        /// "Sync photos" is off.
        case photosOff
        /// It's gone from the Photos library.
        case notInLibrary
        /// "Only favorites" is on and it isn't one.
        case notFavorite
        /// It's hidden now, and Hidden isn't what brought it.
        case hidden
        /// Its album is gone, or it was taken out of the album. A loose
        /// photo that's now in an album goes in that album's folder instead.
        case notInAlbum
        /// Its album isn't chosen any more.
        case albumNotChosen
        /// It came from "Automatically include photos from", and is now
        /// older than that, or that's off.
        case notRecent
    }

    let key: String
    let assetID: String
    let albumTitle: String?
    let path: CardPath
    let cardSize: UInt64
    let reason: Reason
    var id: CardPath { path }
}

/// A grid on the Q2 that holds more photos than Q2 Pod shows.
struct PhotoLimitWarning: Sendable, Hashable {
    /// The album's title, or `nil` for All Photos.
    let albumTitle: String?
    /// How many photos it will have.
    let count: Int
}

/// The photo part of a sync.
struct PhotoPlan: Sendable, Equatable {
    var copies: [PhotoCopy] = []
    /// Photos no longer wanted. All need the user's "remove" choice.
    var removals: [PhotoRemoval] = []
    /// Records whose file is gone from the card and that aren't wanted.
    var forgotten: [String] = []
    /// Wanted photos already on the card as Q2 Sync wrote them.
    var unchangedPhotos = 0
    /// All Photos and albums with more than `PhotoPlanner.maximumPerGrid`.
    var overLimit: [PhotoLimitWarning] = []
    /// Album folders the card will have, if more than Q2 Pod lists.
    var tooManyAlbums: Int?
    /// Set when photos weren't planned at all, e.g. the Photos library
    /// couldn't be read. Shown in the review sheet; nothing changes.
    var note: String?

    var bytesToCopy: UInt64 { copies.reduce(0) { $0 + $1.estimatedSize } }
    var bytesFreedByRemovals: UInt64 { removals.reduce(0) { $0 + $1.cardSize } }
    var photosToAdd: Int { copies.filter { $0.kind == .add }.count }
    var photosToUpdate: Int { copies.filter { $0.kind == .update }.count }

    var isEmpty: Bool { copies.isEmpty && removals.isEmpty && forgotten.isEmpty }
}

/// Builds the photo plan. Pure: changes nothing.
enum PhotoPlanner {

    /// Q2 Pod's `PHOTOS_MAX`: photos shown per grid.
    static let maximumPerGrid = 500

    /// Q2 Pod's `ALBUMS_MAX`: album folders listed.
    static let maximumAlbums = 200

    /// Estimated size of a screen-size copy (750 × 580 JPEG).
    static let screenCopySize: UInt64 = 120_000

    /// The manifest key for a photo in a folder.
    static func key(assetID: String, albumID: String?) -> String {
        "\(assetID)|\(albumID ?? "")"
    }

    /// One photo wanted in one folder.
    private struct Placement {
        let asset: PhotoAsset
        let album: PhotoAlbum?
        var key: String { PhotoPlanner.key(assetID: asset.id, albumID: album?.id) }
    }

    /// - Parameters:
    ///   - library: Every photo and album in the Photos library.
    ///   - selection: The Q2's Photos settings.
    ///   - manifest: The card's manifest.
    ///   - card: What's in `Photos/` now, loose files included.
    ///   - folderName: The profile's photos folder (`Photos`).
    ///   - now: When the sync starts, for "Automatically include photos from".
    ///   - calendar: For that period and the date in file names (its time zone).
    static func plan(library: PhotoLibraryContents, selection: PhotoSelection, manifest: SyncManifest,
                     card: CardFolderListing, folderName: String,
                     now: Date = .now, calendar: Calendar = .current) -> PhotoPlan {
        var plan = PhotoPlan()
        guard selection.source == .photosLibrary else {
            plan.note = "Syncing photos from a folder isn't available yet, so photos were left as they are."
            return plan
        }
        let records = manifest.photos ?? [:]
        let placements = selection.isEnabled ? wanted(library: library, selection: selection,
                                                      now: now, calendar: calendar) : []
        let wantedKeys = Set(placements.map(\.key))

        // Paths spoken for: Q2 Sync's own photos and everything else on the
        // card. Which album owns each recorded folder.
        var usedPaths = Set(records.values.map { CardLayout.caseKey($0.path) }).union(card.files.keys)
        var folderByAlbum: [String: CardPath] = [:]
        var albumByFolder: [String: String] = [:]
        for (_, record) in records.sorted(by: { $0.key < $1.key }) {
            guard let albumID = record.albumID else { continue }
            folderByAlbum[albumID] = folderByAlbum[albumID] ?? record.folder
            albumByFolder[CardLayout.caseKey(record.folder)] = albumByFolder[CardLayout.caseKey(record.folder)] ?? albumID
        }

        var perFolder: [String: (title: String?, count: Int)] = [:]
        for placement in placements {
            let folder = placement.album.map {
                albumFolder(for: $0, folderName: folderName, folderByAlbum: &folderByAlbum, albumByFolder: &albumByFolder)
            } ?? folderName
            if let album = placement.album {
                perFolder[CardLayout.caseKey(folder), default: (album.title, 0)].count += 1
            }
            if let record = records[placement.key] {
                let onCard = card.files[CardLayout.caseKey(record.path)]
                let edited = (placement.asset.modified ?? .distantPast) > (record.modified ?? .distantPast)
                if let onCard, onCard.size == record.cardSize, !edited,
                   record.fullResolution == selection.fullResolution {
                    plan.unchangedPhotos += 1
                } else {
                    plan.copies.append(copy(placement, kind: .update, to: record.path, selection: selection))
                }
                continue
            }
            let preferred = "\(folder)/\(fileName(for: placement.asset, calendar: calendar))"
            var path = preferred
            var number = 2
            while usedPaths.contains(CardLayout.caseKey(path)) {
                path = CardLayout.variant(of: preferred, number: number)
                number += 1
            }
            usedPaths.insert(CardLayout.caseKey(path))
            plan.copies.append(copy(placement, kind: .add, to: path, selection: selection))
        }

        // Q2 Pod's limits: warn, but copy everything.
        if placements.count > maximumPerGrid {
            plan.overLimit.append(PhotoLimitWarning(albumTitle: nil, count: placements.count))
        }
        for (_, folder) in perFolder.sorted(by: { SortKey.compare($0.key, $1.key) })
        where folder.count > maximumPerGrid {
            plan.overLimit.append(PhotoLimitWarning(albumTitle: folder.title, count: folder.count))
        }
        let albumFolders = Set(card.folders).union(perFolder.keys).count
        if albumFolders > maximumAlbums { plan.tooManyAlbums = albumFolders }

        // Photos Q2 Sync copied that are no longer wanted.
        let assets = library.assetsByID
        let albums = Dictionary(library.albums.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (key, record) in records where !wantedKeys.contains(key) {
            guard let onCard = card.files[CardLayout.caseKey(record.path)] else {
                plan.forgotten.append(key)
                continue
            }
            let reason = removalReason(record, asset: assets[record.assetID], albums: albums, selection: selection)
            plan.removals.append(PhotoRemoval(key: key, assetID: record.assetID, albumTitle: record.albumTitle,
                                              path: record.path, cardSize: onCard.size, reason: reason))
        }
        plan.copies.sort { SortKey.compare($0.destination, $1.destination) }
        plan.removals.sort { SortKey.compare($0.path, $1.path) }
        plan.forgotten.sort()
        return plan
    }

    /// The photo's card file name: `YYYY-MM-DD <original name>.jpg`, sanitised.
    static func fileName(for asset: PhotoAsset, calendar: Calendar = .current) -> String {
        let d = calendar.dateComponents([.year, .month, .day], from: asset.created)
        let date = String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
        let original = asset.originalFileName.map { ($0 as NSString).deletingPathExtension } ?? ""
        let name = original.trimmingCharacters(in: .whitespaces).isEmpty ? "Photo" : original
        return FilenameSanitizer.sanitizeFileName(base: "\(date) \(name)", fileExtension: "jpg", fallback: "Photo")
    }

    /// A guess at the card file's size: a fixed size for screen-size
    /// copies; for full resolution, about a third of a byte per pixel
    /// (a JPEG of a camera photo at quality 0.85).
    static func estimatedCardSize(for asset: PhotoAsset, fullResolution: Bool) -> UInt64 {
        guard fullResolution else { return screenCopySize }
        let pixels = UInt64(max(asset.pixelWidth, 0)) * UInt64(max(asset.pixelHeight, 0))
        return max(pixels / 3, screenCopySize)
    }

    // MARK: - Choosing

    /// Every photo the settings want, with its folder: albums in the
    /// library's order, then loose photos; photos oldest first in each.
    private static func wanted(library: PhotoLibraryContents, selection: PhotoSelection,
                               now: Date, calendar: Calendar) -> [Placement] {
        let assets = library.assetsByID
        func keeps(_ asset: PhotoAsset, in album: PhotoAlbum?) -> Bool {
            if selection.onlyFavorites && !asset.isFavorite { return false }
            return !asset.isHidden || album?.kind == .hidden
        }
        func ordered(_ list: [PhotoAsset]) -> [PhotoAsset] {
            list.sorted { ($0.created, $0.id) < ($1.created, $1.id) }
        }

        let chosenAlbums = library.albums.filter(selection.isTicked)
        var placements: [Placement] = []
        var inChosenAlbum = Set<String>()
        for album in chosenAlbums {
            var seen = Set<String>()
            let photos = album.assetIDs.compactMap { assets[$0] }.filter { seen.insert($0.id).inserted }
            for asset in ordered(photos) where keeps(asset, in: album) {
                placements.append(Placement(asset: asset, album: album))
                inChosenAlbum.insert(asset.id)
            }
        }

        let loose: [PhotoAsset]
        if selection.includesAll {
            // Photos in no user album, so All Photos shows every photo.
            let inUserAlbum = Set(library.albums.filter { $0.kind.isIncludedByAll }.flatMap(\.assetIDs))
            loose = library.assets.filter { !inUserAlbum.contains($0.id) }
        } else if let window = selection.effectiveRecentWindow {
            let start = window.startDate(before: now, calendar: calendar)
            loose = library.assets.filter { $0.created >= start && !inChosenAlbum.contains($0.id) }
        } else {
            loose = []
        }
        placements += ordered(loose).filter { keeps($0, in: nil) }.map { Placement(asset: $0, album: nil) }
        return placements
    }

    /// Why a recorded photo is no longer wanted.
    private static func removalReason(_ record: PhotoRecord, asset: PhotoAsset?, albums: [String: PhotoAlbum],
                                      selection: PhotoSelection) -> PhotoRemoval.Reason {
        guard selection.isEnabled else { return .photosOff }
        guard let asset else { return .notInLibrary }
        if selection.onlyFavorites && !asset.isFavorite { return .notFavorite }
        if let albumID = record.albumID {
            guard let album = albums[albumID], album.assetIDs.contains(asset.id) else { return .notInAlbum }
            if !selection.isTicked(album) { return .albumNotChosen }
            return asset.isHidden ? .hidden : .albumNotChosen
        }
        if asset.isHidden { return .hidden }
        // A loose photo under "All" that's wanted no more is now in an album.
        return selection.includesAll ? .notInAlbum : .notRecent
    }

    // MARK: - Naming

    /// The album's folder: the one its recorded photos are in, else
    /// `Photos/<album title>` — shared with the user's own folder of that
    /// name, but not with another album Q2 Sync manages ("Title (2)" then).
    private static func albumFolder(for album: PhotoAlbum, folderName: String,
                                    folderByAlbum: inout [String: CardPath],
                                    albumByFolder: inout [String: String]) -> CardPath {
        if let folder = folderByAlbum[album.id] { return folder }
        let preferred = "\(folderName)/" + FilenameSanitizer.sanitizeComponent(album.title, fallback: "Album")
        let otherAlbums = Set(albumByFolder.filter { $0.value != album.id }.keys)
        let folder = AudiobookPlanner.freeFolder(preferred, taken: otherAlbums)
        folderByAlbum[album.id] = folder
        albumByFolder[CardLayout.caseKey(folder)] = album.id
        return folder
    }

    private static func copy(_ placement: Placement, kind: PhotoCopy.Kind, to path: CardPath,
                             selection: PhotoSelection) -> PhotoCopy {
        PhotoCopy(kind: kind, assetID: placement.asset.id, albumID: placement.album?.id,
                  albumTitle: placement.album?.title, destination: path, modified: placement.asset.modified,
                  fullResolution: selection.fullResolution,
                  estimatedSize: estimatedCardSize(for: placement.asset, fullResolution: selection.fullResolution))
    }
}
