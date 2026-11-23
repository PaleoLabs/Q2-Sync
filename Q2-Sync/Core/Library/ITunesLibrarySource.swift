//
//  ITunesLibrarySource.swift
//  Q2-Sync › Core › Library
//
//  PURPOSE
//  Reads the real Apple Music library using Apple's `iTunesLibrary`
//  framework (`ITLibrary`) and converts it into our own `LibrarySnapshot`.
//
//  HOW IT FITS
//  This is the ONLY file in the app that imports `iTunesLibrary`. Every
//  Apple object is converted into a plain `Track` / `Playlist` value right
//  here, and the Apple objects are thrown away. Nothing outside this file
//  can reach the library.
//
//  SAFETY
//  • `ITLibrary` is a read-only API: it has no methods that modify the
//    library. We never touch Music's database files directly.
//  • We never open audio files here. We only ask the file system whether a
//    file exists (`fileExists`), which reads nothing and changes nothing.
//  • The app's sandbox entitlement `com.apple.security.assets.music.read-only`
//    grants read-only access to ~/Music. Even a bug can't write there:
//    macOS itself would refuse.
//  • Cloud-only items are never downloaded. We only read the flag that says
//    they're in the cloud.
//

import Foundation
import iTunesLibrary

/// Reads album artwork from the Apple Music library, for album covers.
///
/// READ-ONLY: it opens its own `ITLibrary` (a read-only API) the first time
/// artwork is asked for, from the sync's background thread, and only ever
/// reads `artwork.imageData`. Marked `@unchecked Sendable` because its
/// state is guarded by `lock`.
final class LibraryArtworkReader: AlbumArtworkProviding, @unchecked Sendable {

    private let trackIDs: Set<PersistentID>
    private let apiVersion: String
    private let lock = NSLock()
    private var library: ITLibrary?
    private var items: [PersistentID: ITLibMediaItem]?

    init(trackIDs: Set<PersistentID>, apiVersion: String) {
        self.trackIDs = trackIDs
        self.apiVersion = apiVersion
    }

    func artworkData(for trackID: PersistentID) -> Data? {
        lock.withLock {
            if items == nil {
                // Opened once, on first use. If it can't be opened, there's
                // simply no artwork (the sync carries on without covers).
                library = try? ITLibrary(apiVersion: apiVersion)
                var found: [PersistentID: ITLibMediaItem] = [:]
                for item in library?.allMediaItems ?? [] {
                    let id = ITunesLibrarySource.hexID(item.persistentID)
                    if trackIDs.contains(id) { found[id] = item }
                }
                items = found
            }
            return items?[trackID]?.artwork?.imageData
        }
    }
}

/// Song file locations from earlier reads, so a re-read doesn't ask the
/// library service for every song's file again.
///
/// WHY
/// `ITLibMediaItem.location` is a synchronous round trip to macOS's library
/// service (AMPLibraryAgent), which also attaches sandbox access to the URL.
/// The first read of ~10,000 songs takes seconds; every later read in the
/// same run got far slower (83 s, then minutes: "Reading your library…"
/// never finished). A song whose size and modification date haven't changed
/// is in the same file, so its earlier URL (with its access) is reused.
final class SongLocationCache: @unchecked Sendable {

    private struct Entry {
        let size: UInt64
        let modified: Date?
        let url: URL
    }

    private let lock = NSLock()
    private var entries: [PersistentID: Entry] = [:]

    /// The remembered URL, if the song's size and date still match and the
    /// file is still there.
    func url(for id: PersistentID, size: UInt64, modified: Date?) -> URL? {
        let entry = lock.withLock { entries[id] }
        guard let entry, entry.size == size, entry.modified == modified,
              FileManager.default.fileExists(atPath: entry.url.path) else { return nil }
        return entry.url
    }

    func remember(_ url: URL, for id: PersistentID, size: UInt64, modified: Date?) {
        lock.withLock { entries[id] = Entry(size: size, modified: modified, url: url) }
    }
}

/// The real Apple Music library, read through `ITLibrary`.
struct ITunesLibrarySource: LibrarySource {

    /// The ITLibrary API version we ask for. "1.1" is the newest version
    /// Apple documents; it includes `mediaFolderLocation`.
    private let apiVersion = "1.1"

    /// File locations remembered across reads (see `SongLocationCache`).
    private let locations = SongLocationCache()

    /// Creates the source. Nothing is read until `loadSnapshot()` runs.
    init() {}

    /// Reads the whole library and returns a snapshot.
    ///
    /// `@concurrent` tells Swift to run this function on a background
    /// thread instead of the caller's thread. ITLibrary loads the entire
    /// library into memory, which can take a few seconds for ~10,000 songs,
    /// and we don't want the window to freeze meanwhile.
    ///
    /// - Returns: All music tracks and user playlists.
    /// - Throws: `LibraryError.accessDenied` if ITLibrary can't open the library.
    /// - Side effects: None (read-only). May trigger macOS's one-time
    ///   "allow access to Apple Music" permission prompt.
    @concurrent
    func loadSnapshot() async throws -> LibrarySnapshot {
        let library: ITLibrary
        do {
            library = try ITLibrary(apiVersion: apiVersion)
        } catch {
            throw LibraryError.accessDenied(underlying: error.localizedDescription)
        }

        // Keep only music: songs (and "unknown" kinds that are audio files,
        // which older imports sometimes have). Videos, podcasts, audiobooks,
        // ringtones, etc. are excluded per the app's requirements.
        let musicItems = library.allMediaItems.filter(Self.isMusic)
        let tracks = musicItems.map { Self.makeTrack($0, locations: locations) }

        // Only playlists that contain music we know about are useful.
        // Apple's built-in "distinguished" playlists are skipped when they
        // aren't song lists worth having (the whole library, Purchased,
        // Movies…); its music smart playlists (My Top Rated…) are kept.
        let knownIDs = Set(tracks.map(\.id))
        let playlists = library.allPlaylists
            .filter(Self.isUserPlaylist)
            .map { Self.makePlaylist($0, keepingOnly: knownIDs) }

        return LibrarySnapshot(
            tracks: tracks,
            playlists: playlists,
            mediaFolderURL: library.mediaFolderLocation
        )
    }

    // MARK: - Filtering

    /// `true` for items we treat as music.
    ///
    /// - Parameter item: An Apple media item.
    /// - Returns: Whether it belongs in the sync selection.
    private static func isMusic(_ item: ITLibMediaItem) -> Bool {
        if item.isVideo { return false }
        switch item.mediaKind {
        case .kindSong:
            return true
        case .kindUnknown:
            // Some old imports are "unknown" but are plain audio files.
            return item.locationType == .file
        default:
            return false
        }
    }

    /// Apple's built-in playlists that are ordinary lists of songs, created
    /// in every library (and editable as smart playlists), so they're kept.
    private static let musicDistinguishedKinds: Set<ITLibDistinguishedPlaylistKind> = [
        .kind90sMusic, .kindMyTopRated, .kindTop25MostPlayed, .kindRecentlyPlayed,
        .kindRecentlyAdded, .kindClassicalMusic, .kindLovedSongs,
    ]

    /// `true` for playlists worth putting on the Q2: the user's own (regular,
    /// smart, Genius, folders) and Apple's music smart playlists. Hidden
    /// lists, the library itself, and built-in lists that aren't songs
    /// (Purchased, Movies, Podcasts, Voice Memos…) are left out.
    private static func isUserPlaylist(_ playlist: ITLibPlaylist) -> Bool {
        guard playlist.isVisible, !playlist.isPrimary else { return false }
        return playlist.distinguishedKind == .kindNone || musicDistinguishedKinds.contains(playlist.distinguishedKind)
    }

    // MARK: - Conversion

    /// Converts an Apple media item into our `Track` value.
    ///
    /// - Parameter item: The Apple object (only read, never modified).
    /// - Returns: A plain, `Sendable` copy of the fields we need.
    private static func makeTrack(_ item: ITLibMediaItem, locations: SongLocationCache) -> Track {
        let id = hexID(item.persistentID)
        var fileURL: URL?
        if item.locationType == .file {
            // `location` is slow (see `SongLocationCache`): reuse it when the
            // song hasn't changed since the last read.
            if let known = locations.url(for: id, size: item.fileSize, modified: item.modifiedDate) {
                fileURL = known
            } else if let url = item.location {
                locations.remember(url, for: id, size: item.fileSize, modified: item.modifiedDate)
                fileURL = url
            }
        }

        // Titles are almost always set, but fall back to the file name
        // so the UI never shows an empty row.
        let title = item.title.nonEmpty
            ?? fileURL?.deletingPathExtension().lastPathComponent
            ?? "Untitled"

        return Track(
            id: id,
            title: title,
            artist: item.artist?.name?.nonEmpty,
            albumArtist: item.album.albumArtist?.nonEmpty,
            album: item.album.title?.nonEmpty,
            genre: item.genre.nonEmpty,
            trackNumber: item.trackNumber,
            discNumber: item.album.discNumber,
            discCount: item.album.discCount,
            isCompilation: item.album.isCompilation,
            durationSeconds: Double(item.totalTime) / 1000.0,
            fileSize: item.fileSize,
            fileURL: fileURL,
            fileKind: item.kind,
            modifiedDate: item.modifiedDate,
            availability: availability(of: item, fileURL: fileURL),
            hasArtwork: item.hasArtworkAvailable,
            year: item.year > 0 ? item.year : nil,
            composer: item.composer.nonEmpty,
            bitRate: item.bitrate > 0 ? item.bitrate : nil,
            sampleRate: item.sampleRate > 0 ? item.sampleRate : nil,
            playCount: item.playCount,
            dateAdded: item.addedDate,
            lastPlayed: item.lastPlayedDate
        )
    }

    /// Decides whether a track can be copied, and if not, why.
    ///
    /// The order of checks matters: DRM is reported before "missing" so the
    /// report tells the user the most useful reason.
    ///
    /// - Parameters:
    ///   - item: The Apple media item.
    ///   - fileURL: Its local file, if it has one.
    /// - Returns: The availability category.
    /// - Side effects: Calls `FileManager.fileExists`, which only checks
    ///   for the file's presence. Nothing is opened, read, or downloaded.
    private static func availability(of item: ITLibMediaItem, fileURL: URL?) -> TrackAvailability {
        if item.isDRMProtected { return .drmProtected }
        guard let fileURL else {
            // No local file: either it's in iCloud only, or it's a stream.
            return item.isCloud || item.locationType == .remote ? .cloudOnly : .unsupported
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // A cloud item that was never downloaded can still have a
            // location; report it as cloud-only rather than "missing".
            return item.isCloud ? .cloudOnly : .fileMissing
        }
        return .available
    }

    /// Converts an Apple playlist into our `Playlist` value.
    ///
    /// - Parameters:
    ///   - playlist: The Apple playlist (only read).
    ///   - knownIDs: IDs of tracks we kept; others (videos etc.) are dropped.
    /// - Returns: A plain copy with its track IDs in order.
    private static func makePlaylist(_ playlist: ITLibPlaylist, keepingOnly knownIDs: Set<PersistentID>) -> Playlist {
        let kind: PlaylistKind
        switch playlist.kind {
        case .smart:  kind = .smart
        case .folder: kind = .folder
        default:      kind = .regular
        }

        // Folders report the tracks of their children as their own items;
        // we store no tracks for folders to avoid writing them twice.
        let trackIDs = kind == .folder
            ? []
            : playlist.items.map { hexID($0.persistentID) }.filter(knownIDs.contains)

        return Playlist(
            id: hexID(playlist.persistentID),
            name: playlist.name,
            kind: kind,
            parentID: playlist.parentID.map(hexID),
            trackIDs: trackIDs
        )
    }

    /// A reader for these tracks' artwork (opened when first used).
    func artworkReader(for trackIDs: Set<PersistentID>) -> (any AlbumArtworkProviding)? {
        trackIDs.isEmpty ? nil : LibraryArtworkReader(trackIDs: trackIDs, apiVersion: apiVersion)
    }

    /// Formats Apple's 64-bit persistent ID as 16 uppercase hex digits.
    ///
    /// - Parameter number: The `NSNumber` ITLibrary gives us.
    /// - Returns: e.g. `"00A1B2C3D4E5F607"`.
    static func hexID(_ number: NSNumber) -> PersistentID {
        String(format: "%016llX", number.uint64Value)
    }
}
