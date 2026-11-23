//
//  LibraryModel.swift
//  Q2-Sync › App
//
//  PURPOSE
//  Holds the app's current view of the Apple Music library for the UI:
//  whether it's loading, the latest snapshot, its health, and any error.
//
//  HOW IT FITS
//      LibrarySource (Core) ──loadSnapshot()──▶ LibraryModel ──observed by──▶ Views
//
//  SWIFT FEATURES USED HERE
//  • `@Observable` (a macro from the Observation framework) makes SwiftUI
//    automatically redraw any view that reads a property of this class
//    when that property changes. No manual "publish" calls needed.
//  • `@MainActor` means every property and method runs on the main
//    thread. UI state must only change on the main thread, and marking the
//    whole class guarantees that at compile time.
//

import Foundation
import Observation
import OSLog

/// UI-facing state for the Apple Music library.
@MainActor
@Observable
final class LibraryModel {

    /// The loading lifecycle, shown by the views.
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// Where loading currently stands.
    private(set) var state: LoadState = .idle

    /// The most recently loaded snapshot, if any.
    private(set) var snapshot: LibrarySnapshot?

    /// Result of the "Mac looks empty" check for the current snapshot.
    private(set) var health: LibraryHealth?

    /// How long the last load took, for the prototype's diagnostics.
    private(set) var lastLoadDuration: Duration?

    /// Goes up by one each time a snapshot loads, so views can tell a new
    /// read from the old one cheaply (snapshots aren't `Equatable`).
    private(set) var loadCount = 0

    /// The source we read from. Real library in the app; fixtures in previews.
    private let source: any LibrarySource

    /// Creates the model.
    ///
    /// - Parameter source: Where to read the library from. Defaults to the
    ///   real Apple Music library (read-only).
    /// A read-only reader for these tracks' artwork (for album covers),
    /// or `nil` if the source has none.
    func artworkReader(for trackIDs: Set<PersistentID>) -> (any AlbumArtworkProviding)? {
        source.artworkReader(for: trackIDs)
    }

    /// One song's artwork for the song inspector, read off the main thread.
    /// The reader covers the whole library and is opened on first use (a
    /// second or two), then kept until the library is read again.
    ///
    /// - Parameter trackID: The song.
    /// - Returns: Image data, or `nil` if it has none.
    func artworkData(for trackID: PersistentID) async -> Data? {
        if browserArtwork == nil, let ids = snapshot.map({ Set($0.tracksByID.keys) }) {
            browserArtwork = source.artworkReader(for: ids)
        }
        guard let reader = browserArtwork else { return nil }
        return await Task.detached(priority: .userInitiated) { reader.artworkData(for: trackID) }.value
    }

    /// The inspector's artwork reader (see `artworkData(for:)`).
    @ObservationIgnored private var browserArtwork: (any AlbumArtworkProviding)?

    init(source: any LibrarySource = ITunesLibrarySource()) {
        self.source = source
    }

    /// Loads (or reloads) the library snapshot.
    ///
    /// The `await` hands the slow work to the source's background thread;
    /// while it runs, the main thread stays free to draw the spinner.
    ///
    /// - Side effects: Updates `state`, `snapshot`, `health`. Read-only
    ///   toward the library itself.
    func load() async {
        // Already loading (a double-click, or a sync starting during a
        // read): wait for that load instead of starting another, so the
        // caller sees its result rather than an old or missing snapshot.
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { await performLoad() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    /// The load in progress, shared by everyone who asks for one meanwhile.
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// Reads the library once and updates `state`, `snapshot` and `health`.
    private func performLoad() async {
        state = .loading
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let loaded = try await source.loadSnapshot()
            snapshot = loaded
            browserArtwork = nil // Re-opened on demand for the new read.
            loadCount += 1
            health = LibraryHealthCheck.evaluate(loaded)
            lastLoadDuration = clock.now - start
            state = .loaded
            logSummary(loaded)
        } catch {
            state = .failed(error.localizedDescription)
            Self.logger.error("Library load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Diagnostics

    /// Writes to the macOS unified log (view it in Console.app by
    /// filtering for subsystem "io.github.q2sync.Q2Sync").
    private static let logger = Logger(subsystem: "io.github.q2sync.Q2Sync", category: "library")

    /// Logs a short, counts-only summary of a loaded snapshot.
    ///
    /// Only counts and the health result are logged — never song titles or
    /// file paths — so the system log doesn't collect details of your
    /// library.
    ///
    /// - Parameter snapshot: The snapshot just loaded.
    private func logSummary(_ snapshot: LibrarySnapshot) {
        let counts = snapshot.availabilityCounts
        let byKind = TrackAvailability.allCases
            .map { "\($0.rawValue)=\(counts[$0, default: 0])" }
            .joined(separator: " ")
        let smart = snapshot.playlists.filter { $0.kind == .smart }.count
        let folders = snapshot.playlists.filter { $0.kind == .folder }.count
        let health = health.map { String(describing: $0) } ?? "unknown"
        let mediaFolderKnown = snapshot.mediaFolderURL != nil
        let duration = lastLoadDuration.map { String(describing: $0) } ?? "?"
        Self.logger.notice("""
            Library loaded: tracks=\(snapshot.tracks.count, privacy: .public) \
            \(byKind, privacy: .public) playlists=\(snapshot.playlists.count, privacy: .public) \
            smart=\(smart, privacy: .public) folders=\(folders, privacy: .public) \
            artists=\(snapshot.artistGroups.count, privacy: .public) \
            albums=\(snapshot.albumGroups.count, privacy: .public) \
            genres=\(snapshot.genreGroups.count, privacy: .public) \
            mediaFolderKnown=\(mediaFolderKnown, privacy: .public) \
            health=\(health, privacy: .public) duration=\(duration, privacy: .public)
            """)
    }
}
