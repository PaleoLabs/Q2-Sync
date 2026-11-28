//
//  PhotoLibraryModel.swift
//  Q2-Sync › App
//
//  PURPOSE
//  The Photos library's photos and albums, for the Photos tab, the
//  sidebar's Photos browser and the capacity bar (issue #68). Reads them
//  (read-only) once access to Photos has been allowed.
//
//  HOW IT FITS
//  Owned by `AutoSyncController` with `PhotosAccess`, like
//  `PodcastLibraryModel`. The tab calls `load()` when shown;
//  `SyncCoordinator` reads the library again at each sync through
//  `source`, so a sync never uses an old list.
//

import Foundation
import Observation

@MainActor
@Observable
final class PhotoLibraryModel {

    enum State: Equatable {
        case idle
        case loading
        case loaded(PhotoLibraryContents)
        case failed(String)
    }

    private(set) var state: State = .idle

    /// `true` while the library is being read, including re-reads.
    private(set) var isReading = false

    /// The "looks healthy" check from the last read; `nil` until read.
    private(set) var health: LibraryHealth?

    /// How long the last read took, for the sidebar footer.
    private(set) var readDuration: Duration?

    /// Counts finished reads, so views can tell a re-read apart (comparing
    /// whole libraries would be slow).
    private(set) var loadCount = 0

    /// Access to the Photos library.
    let access: PhotosAccess

    init(access: PhotosAccess) {
        self.access = access
    }

    /// The library last read, or `nil`.
    var contents: PhotoLibraryContents? {
        if case .loaded(let contents) = state { return contents }
        return nil
    }

    /// A source reading the Photos library now, or `nil` without access.
    /// It also renders photos for the card (`PhotoRendering`). Call
    /// `access.refresh()` first if the answer may have changed.
    var source: PhotoKitSource? {
        access.isAllowed ? PhotoKitSource() : nil
    }

    /// Reads (or re-reads) the photos and albums.
    func load() async {
        access.refresh() // Access may have changed in System Settings.
        guard let source else {
            state = .idle
            return
        }
        if case .loaded = state {} else { state = .loading }
        isReading = true
        defer { isReading = false }
        let clock = ContinuousClock()
        let started = clock.now
        do {
            let contents = try await source.loadPhotos()
            health = source.health()
            readDuration = clock.now - started
            state = .loaded(contents)
        } catch {
            health = nil
            state = .failed(error.localizedDescription)
        }
        loadCount += 1
    }

    /// Asks macOS for access to Photos (its privacy prompt, the first
    /// time), then reads the library.
    func allowAccess() async {
        await access.allow()
        await load()
    }
}
