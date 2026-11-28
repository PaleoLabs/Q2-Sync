//
//  PodcastLibraryModel.swift
//  Q2-Sync › App
//
//  PURPOSE
//  The episodes the Podcasts app has downloaded, grouped by show, for the
//  Podcasts tab and the capacity bar. Reads them (read-only) once access
//  to the Podcasts app has been allowed.
//
//  HOW IT FITS
//  Owned by `AutoSyncController` with `PodcastsAccess`, like
//  `AudiobookLibraryModel`. The tab calls `load()` when shown;
//  `SyncCoordinator` reads the episodes again at each sync through
//  `source`, so a sync never uses an old list.
//

import Foundation
import Observation

@MainActor
@Observable
final class PodcastLibraryModel {

    enum State: Equatable {
        case idle
        case loading
        case loaded([PodcastShow])
        case failed(String)
    }

    private(set) var state: State = .idle

    /// `true` while the Podcasts app is being read, including re-reads.
    private(set) var isReading = false

    /// The "looks healthy" check from the last read; `nil` until read.
    private(set) var health: LibraryHealth?

    /// Access to the Podcasts app's folder.
    let access: PodcastsAccess

    init(access: PodcastsAccess) {
        self.access = access
    }

    /// The shows last read (only those with downloaded episodes), or none.
    var shows: [PodcastShow] {
        if case .loaded(let shows) = state { return shows }
        return []
    }

    /// A source reading the Podcasts app now, or `nil` without access.
    var source: (any PodcastSource)? {
        guard access.status == .allowed, let folder = access.folder else { return nil }
        return ApplePodcastsSource(folder: folder)
    }

    /// Reads (or re-reads) the downloaded episodes.
    func load() async {
        guard let source else {
            state = .idle
            return
        }
        if case .loaded = state {} else { state = .loading }
        isReading = true
        defer { isReading = false }
        do {
            let shows = try await source.loadPodcasts()
            health = source.health()
            state = .loaded(shows)
        } catch {
            health = nil
            state = .failed(error.localizedDescription)
        }
    }

    /// Asks for access to the Podcasts app, then reads the episodes.
    ///
    /// - Returns: A message if access wasn't given.
    func allowAccess() async -> String? {
        let problem = access.allow()
        await load()
        return problem
    }
}
