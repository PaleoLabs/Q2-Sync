//
//  Photo.swift
//  Q2-Sync › Core › Models
//
//  PURPOSE
//  Our own, read-only description of the Mac's Photos library (issue #68):
//  each `PhotoAsset` is one photo, and each `PhotoAlbum` lists the photos
//  in one album (a user album, or Favorites, Recently Added, a media type
//  or Hidden).
//
//  HOW IT FITS
//  `PhotoKitSource` (App) reads PhotoKit and turns it into these values.
//  The Photos tab, the sync planner and the capacity bar work only with
//  them. Plain `Sendable` values: nothing here can change the Photos
//  library. Tests use `FixturePhotoSource`, never the real library.
//
//  Albums inside folders are flattened: each keeps its own title for its
//  card folder, and `folderPath` only tells the Photos tab where to list it.
//  There's no People album or Recently Deleted: PhotoKit doesn't offer them.
//

import Foundation

/// One photo in the library. Videos are never listed.
struct PhotoAsset: Codable, Hashable, Identifiable, Sendable {

    /// PhotoKit's local identifier. What the manifest remembers.
    let id: String

    /// When the photo was taken (or added, if PhotoKit has no date). Names
    /// the card file and decides "Automatically include photos from".
    let created: Date

    /// When the photo was last edited, if PhotoKit knows. A later date
    /// than the copy on the card replaces it.
    let modified: Date?

    /// Marked as a favourite in Photos.
    let isFavorite: Bool

    /// In the Hidden album. Hidden photos sync only through Hidden.
    let isHidden: Bool

    /// The full-size image's width and height, in pixels.
    let pixelWidth: Int
    let pixelHeight: Int

    /// The original file's name, e.g. `IMG_1234.HEIC`, if PhotoKit has it.
    let originalFileName: String?

    /// The original's type identifier, e.g. `public.heic`, if known.
    let uniformTypeIdentifier: String?
}

/// What sort of album it is, which decides where the Photos tab lists it
/// and whether "All photos and albums" brings it.
enum PhotoAlbumKind: String, Codable, Hashable, Sendable {

    /// Photos › Favorites.
    case favorites

    /// Photos › Recently Added (Recents' last 30 days).
    case recentlyAdded

    /// Under Media Types: Selfies, Portrait, Panoramas, Screenshots…
    case mediaType

    /// Photos › Hidden. Never ticked by "All".
    case hidden

    /// An album the user made, possibly inside folders.
    case user

    /// `true` if "All photos and albums" puts this album on the card as
    /// its own folder. Only user albums: the smart albums would repeat
    /// photos that are there already, and Hidden must be ticked on purpose.
    var isIncludedByAll: Bool { self == .user }
}

/// One album and its photos.
struct PhotoAlbum: Codable, Hashable, Identifiable, Sendable {

    /// PhotoKit's local identifier. What a Q2's selection remembers.
    let id: String

    /// The album's title. Never empty: falls back to "Album". Names its
    /// card folder (cleaned for the card when planning).
    let title: String

    let kind: PhotoAlbumKind

    /// The folders it sits in, outermost first (empty at the top level).
    /// Only for listing it; the card has one level of album folders.
    let folderPath: [String]

    /// The album's photos (`PhotoAsset.id`), in the album's order.
    let assetIDs: [String]
}

/// Everything read from the Photos library at once.
struct PhotoLibraryContents: Hashable, Sendable {

    /// Every photo, hidden ones included, oldest first.
    let assets: [PhotoAsset]

    /// Favorites, Recently Added, the media types and Hidden, then user
    /// albums in the Photos sidebar's order.
    let albums: [PhotoAlbum]

    init(assets: [PhotoAsset] = [], albums: [PhotoAlbum] = []) {
        self.assets = assets
        self.albums = albums
    }

    /// The photos by ID.
    var assetsByID: [String: PhotoAsset] {
        Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// `true` if there are no photos at all (still a healthy library).
    var isEmpty: Bool { assets.isEmpty }
}

/// Something that can read the Photos library. Reading only.
protocol PhotoSource: Sendable {

    /// Reads every photo and album.
    ///
    /// - Throws: `PhotoError` if Photos access isn't allowed or the
    ///   library can't be read.
    /// - Side effects: None. Reading only.
    func loadPhotos() async throws -> PhotoLibraryContents

    /// The "looks healthy" check (see `PhotoHealthCheck`).
    func health() -> LibraryHealth
}

extension PhotoSource {

    /// Fixtures have no library to check.
    func health() -> LibraryHealth { .healthy }
}

/// Problems reading the Photos library.
enum PhotoError: LocalizedError, Equatable {

    /// The user hasn't allowed (or has refused) access to Photos.
    case notAllowed

    /// PhotoKit couldn't read the library.
    case libraryUnreadable(underlying: String)

    var errorDescription: String? {
        switch self {
        case .notAllowed:
            return "Q2 Sync isn't allowed to read your Photos library. You can allow it in System Settings › Privacy & Security › Photos."
        case .libraryUnreadable(let underlying):
            return "Q2 Sync couldn't read your Photos library: \(underlying)"
        }
    }
}

/// Fixed photos, for tests and previews.
struct FixturePhotoSource: PhotoSource {
    let contents: PhotoLibraryContents
    func loadPhotos() async throws -> PhotoLibraryContents { contents }
}
