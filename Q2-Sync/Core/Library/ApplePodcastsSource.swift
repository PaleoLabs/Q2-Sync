//
//  ApplePodcastsSource.swift
//  Q2-Sync › Core › Library
//
//  PURPOSE
//  Reads the episodes the Podcasts app has downloaded, read-only, as
//  `PodcastShow`s (issue #20).
//
//  WHERE THE PODCASTS APP KEEPS THEM
//  ~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/
//    • Library/Cache/<UUID>.mp3: each downloaded episode. The file's name
//      is the episode's `ZMTEPISODE.ZUUID`.
//    • Documents/MTLibrary.sqlite: a Core Data store (WAL) describing every
//      episode the app knows, downloaded or not. From `ZMTEPISODE`: ZUUID,
//      ZTITLE, ZPUBDATE (seconds since 2001-01-01), ZPLAYSTATE (0 played,
//      1 in progress, 2 unplayed), ZDRMKEYURI (protected episodes), and
//      ZPODCAST → `ZMTPODCAST.Z_PK` (ZUUID, ZTITLE, ZAUTHOR).
//  Seen on macOS 27.2 with 8 shows and 6 downloads. `ZPLAYCOUNT` and
//  `ZHASBEENPLAYED` didn't change when episodes were played, so they're
//  not used.
//
//  SAFETY
//  Reading only. The database is opened `?mode=ro`; Q2 Sync never writes
//  to it (it syncs with iCloud, and there's no supported way to change
//  it). The sandbox reaches the folder only through a read-only bookmark
//  the user granted. A cache file that's a link, or whose real path isn't
//  inside the folder, is never read or copied. A cache file with no
//  database row is left out.
//
//  HOW IT FITS
//  The Podcasts tab and the sync planner ask a `PodcastSource` for shows.
//  Tests use `FixturePodcastSource`, or a database they build themselves,
//  never the real Podcasts app.
//

import Foundation
import SQLite3

/// Something that can list downloaded podcast episodes. Reading only.
protocol PodcastSource: Sendable {

    /// Reads the shows with downloaded episodes, sorted by title, episodes
    /// newest first. An empty list means nothing is downloaded.
    ///
    /// - Throws: `PodcastError` if the folder or database can't be read.
    /// - Side effects: None. Reading only.
    func loadPodcasts() async throws -> [PodcastShow]
}

/// Problems reading the Podcasts app.
enum PodcastError: LocalizedError, Equatable {

    /// The database is missing (Podcasts never used on this Mac).
    case noDatabase

    /// The database couldn't be opened or read.
    case databaseUnreadable(underlying: String)

    /// The downloads folder couldn't be listed.
    case downloadsUnreadable(underlying: String)

    var errorDescription: String? {
        switch self {
        case .noDatabase:
            return "The Podcasts app has no library on this Mac."
        case .databaseUnreadable(let underlying):
            return "Q2 Sync couldn't read the Podcasts app's library. (\(underlying))"
        case .downloadsUnreadable(let underlying):
            return "Q2 Sync couldn't list the Podcasts app's downloads. (\(underlying))"
        }
    }
}

/// The real Podcasts app.
struct ApplePodcastsSource: PodcastSource {

    /// The Podcasts app's group container (the folder the user allows).
    static var defaultFolder: URL {
        PathGuard.realHomeDirectory.appending(
            path: "Library/Group Containers/243LU875E5.groups.com.apple.podcasts",
            directoryHint: .isDirectory)
    }

    /// The database, inside that folder.
    static let databasePath = "Documents/MTLibrary.sqlite"

    /// The downloads, inside that folder.
    static let downloadsPath = "Library/Cache"

    /// The Podcasts folder, already accessible (security scope started).
    let folder: URL

    init(folder: URL = ApplePodcastsSource.defaultFolder) {
        self.folder = folder
    }

    func loadPodcasts() async throws -> [PodcastShow] {
        let files = try PodcastDownloads.list(in: folder.appending(path: Self.downloadsPath, directoryHint: .isDirectory),
                                              folder: folder)
        guard !files.isEmpty else { return [] }
        let rows = try PodcastDatabase.rows(at: folder.appending(path: Self.databasePath),
                                            episodeIDs: Set(files.map(\.id)))
        return PodcastLibrary.shows(files: files, rows: rows)
    }
}

// MARK: - Downloads folder

/// One file in the Podcasts app's downloads folder.
struct PodcastDownload: Hashable, Sendable {
    /// The file name without its extension: the episode's UUID.
    let id: String
    let url: URL
    let size: UInt64
    let kind: PodcastEpisodeKind
}

/// Lists the downloads folder.
enum PodcastDownloads {

    /// The audio and video files directly in `downloads`. Hidden files,
    /// links, folders, other file types and anything whose real path is
    /// outside `folder` are left out.
    ///
    /// - Throws: `PodcastError.downloadsUnreadable` if it can't be listed.
    ///   A missing folder means nothing is downloaded (empty list).
    static func list(in downloads: URL, folder: URL) throws -> [PodcastDownload] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: downloads.path) else { return [] }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let items: [URL]
        do {
            items = try fm.contentsOfDirectory(at: downloads, includingPropertiesForKeys: keys,
                                               options: [.skipsHiddenFiles])
        } catch {
            throw PodcastError.downloadsUnreadable(underlying: error.localizedDescription)
        }
        let folderPath = PathGuard.realPath(folder.path) ?? folder.standardizedFileURL.path
        return items.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isSymbolicLink != true, values?.isRegularFile == true,
                  let kind = PodcastEpisodeKind(fileExtension: url.pathExtension),
                  let real = PathGuard.realPath(url.path), PathGuard.isInside(real, folder: folderPath) else { return nil }
            let id = url.deletingPathExtension().lastPathComponent
            guard !id.isEmpty else { return nil }
            return PodcastDownload(id: id, url: url, size: UInt64(values?.fileSize ?? 0), kind: kind)
        }
    }
}

// MARK: - Database

/// What the database says about one episode.
struct PodcastEpisodeRow: Hashable, Sendable {
    var episodeID: String
    var title: String?
    /// `ZPUBDATE`: seconds since 2001-01-01.
    var published: Double?
    var playState: Int?
    var drmKeyURI: String?
    var showID: String?
    var showTitle: String?
    var showAuthor: String?
}

/// Reads `MTLibrary.sqlite`, read-only.
enum PodcastDatabase {

    /// Episode columns read, if the database has them. `ZUUID` and
    /// `ZPODCAST` are required; any other that's missing reads as `NULL`,
    /// so a later Podcasts version that drops one still works.
    private static let episodeColumns = ["ZTITLE", "ZPUBDATE", "ZPLAYSTATE", "ZDRMKEYURI"]
    private static let showColumns = ["ZUUID", "ZTITLE", "ZAUTHOR"]

    /// The rows for these episode UUIDs (others are never read).
    ///
    /// - Throws: `PodcastError.noDatabase` if the file is missing,
    ///   `.databaseUnreadable` if it can't be opened or queried.
    /// - Side effects: None. Opens the database read-only.
    static func rows(at url: URL, episodeIDs: Set<String>) throws -> [PodcastEpisodeRow] {
        guard FileManager.default.fileExists(atPath: url.path) else { throw PodcastError.noDatabase }
        guard !episodeIDs.isEmpty else { return [] }

        // `file:` URI with mode=ro: read-only even if the file is writable.
        var components = URLComponents()
        components.scheme = "file"
        components.path = url.path
        components.queryItems = [URLQueryItem(name: "mode", value: "ro")]
        guard let uri = components.string else { throw PodcastError.databaseUnreadable(underlying: "bad path") }

        var handle: OpaquePointer?
        let opened = sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        defer { sqlite3_close(handle) }
        guard opened == SQLITE_OK, let db = handle else {
            throw PodcastError.databaseUnreadable(underlying: handle.map { message($0) } ?? "can't open")
        }
        sqlite3_busy_timeout(db, 2000)

        let episodeHas = try columns(of: "ZMTEPISODE", in: db)
        let showHas = try columns(of: "ZMTPODCAST", in: db)
        guard episodeHas.contains("ZUUID"), episodeHas.contains("ZPODCAST"), showHas.contains("Z_PK") else {
            throw PodcastError.databaseUnreadable(underlying: "unexpected layout")
        }
        let select = ["e.ZUUID"]
            + episodeColumns.map { episodeHas.contains($0) ? "e.\($0)" : "NULL" }
            + showColumns.map { showHas.contains($0) ? "p.\($0)" : "NULL" }
        let ids = episodeIDs.sorted()
        let sql = "SELECT \(select.joined(separator: ", ")) FROM ZMTEPISODE e "
            + "LEFT JOIN ZMTPODCAST p ON p.Z_PK = e.ZPODCAST "
            + "WHERE e.ZUUID IN (\(Array(repeating: "?", count: ids.count).joined(separator: ",")))"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw PodcastError.databaseUnreadable(underlying: message(db))
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, id) in ids.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), id, -1, transient)
        }

        var rows: [PodcastEpisodeRow] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw PodcastError.databaseUnreadable(underlying: message(db)) }
            guard let id = text(statement, 0) else { continue }
            rows.append(PodcastEpisodeRow(
                episodeID: id, title: text(statement, 1), published: double(statement, 2),
                playState: double(statement, 3).map { Int($0) }, drmKeyURI: text(statement, 4),
                showID: text(statement, 5), showTitle: text(statement, 6), showAuthor: text(statement, 7)))
        }
        return rows
    }

    private static func columns(of table: String, in db: OpaquePointer) throws -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw PodcastError.databaseUnreadable(underlying: message(db)) }
        defer { sqlite3_finalize(statement) }
        var names = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = text(statement, 1) { names.insert(name) }
        }
        return names
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }

    private static func double(_ statement: OpaquePointer, _ column: Int32) -> Double? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_double(statement, column)
    }

    private static func message(_ db: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(db))
    }
}

// MARK: - Putting it together

/// Joins downloads with database rows. No file or database access, so
/// it's easy to test.
enum PodcastLibrary {

    /// The shows with downloaded episodes: titles sorted like Finder,
    /// episodes newest first. A download with no row is left out.
    static func shows(files: [PodcastDownload], rows: [PodcastEpisodeRow]) -> [PodcastShow] {
        var rowByID: [String: PodcastEpisodeRow] = [:]
        for row in rows { rowByID[row.episodeID] = row }

        var episodesByShow: [String: [PodcastEpisode]] = [:]
        var showInfo: [String: (title: String, author: String?)] = [:]
        for file in files {
            guard let row = rowByID[file.id] else { continue }
            let showTitle = cleaned(row.showTitle) ?? "Podcast"
            // Episodes without a show row are grouped under their title.
            let showID = cleaned(row.showID) ?? "untitled:\(showTitle)"
            showInfo[showID] = showInfo[showID] ?? (showTitle, cleaned(row.showAuthor))
            episodesByShow[showID, default: []].append(PodcastEpisode(
                id: file.id, showID: showID, showTitle: showTitle,
                title: cleaned(row.title) ?? "Episode",
                published: row.published.map { Date(timeIntervalSinceReferenceDate: $0) },
                fileURL: file.url, fileSize: file.size, kind: file.kind,
                playState: PodcastPlayState(databaseValue: row.playState),
                isProtected: cleaned(row.drmKeyURI) != nil))
        }
        return episodesByShow.map { id, episodes in
            PodcastShow(id: id, title: showInfo[id]?.title ?? "Podcast", author: showInfo[id]?.author,
                        episodes: episodes.sorted(by: newestFirst))
        }
        .sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    /// Newest first; undated last; ties by title, then id.
    static func newestFirst(_ a: PodcastEpisode, _ b: PodcastEpisode) -> Bool {
        switch (a.published, b.published) {
        case let (x?, y?) where x != y: return x > y
        case (_?, nil): return true
        case (nil, _?): return false
        default:
            let order = a.title.localizedStandardCompare(b.title)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// A fake Podcasts library for tests and previews.
struct FixturePodcastSource: PodcastSource {
    let shows: [PodcastShow]
    func loadPodcasts() async throws -> [PodcastShow] { shows }
}
