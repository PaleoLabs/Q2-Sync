//
//  AudiobookLibraryModel.swift
//  Q2-Sync › App
//
//  PURPOSE
//  The audiobooks in Apple Books, for the Audiobooks tab and for syncing.
//  Reads them (read-only) once access to Apple Books has been allowed.
//
//  HOW IT FITS
//  Owned by `AutoSyncController` with `BooksAccess`. The tab calls
//  `load()` when shown; `SyncCoordinator` reads the books again at each
//  sync through `source`, so a sync never uses an old list.
//

import Foundation
import Observation

@MainActor
@Observable
final class AudiobookLibraryModel {

    enum State: Equatable {
        case idle
        case loading
        case loaded([Audiobook])
        case failed(String)
    }

    private(set) var state: State = .idle

    /// `true` while Apple Books is being read, including re-reads (which
    /// keep the old list showing in `state`).
    private(set) var isReading = false

    /// The "looks healthy" check for every book last read; `nil` until read.
    private(set) var health: LibraryHealth?

    /// The source of the last read, for `health(for:)`.
    @ObservationIgnored private var lastSource: (any AudiobookSource)?

    /// Access to Apple Books' folder.
    let access: BooksAccess

    init(access: BooksAccess) {
        self.access = access
    }

    /// The books last read, or none.
    var books: [Audiobook] {
        if case .loaded(let books) = state { return books }
        return []
    }

    /// A source reading Apple Books now, or `nil` without access.
    var source: (any AudiobookSource)? {
        guard access.status == .allowed, let folder = access.folder else { return nil }
        return AppleBooksSource(folder: folder)
    }

    /// Reads (or re-reads) the audiobooks.
    func load() async {
        guard let source else {
            state = .idle
            return
        }
        if case .loaded = state {} else { state = .loading }
        isReading = true
        defer { isReading = false }
        do {
            let books = try await source.loadAudiobooks()
            lastSource = source
            health = source.health(of: books, selection: nil)
            state = .loaded(books)
        } catch AudiobookError.noBooksList {
            lastSource = source
            health = source.health(of: [], selection: nil)
            state = .loaded([])
        } catch {
            health = nil
            state = .failed(error.localizedDescription)
        }
    }

    /// The "looks healthy" check for the books a Q2 chooses, or `nil` until read.
    ///
    /// - Parameter selection: That Q2's audiobook choice.
    func health(for selection: AudiobookSelection) -> LibraryHealth? {
        guard case .loaded(let books) = state, let lastSource else { return nil }
        return lastSource.health(of: books, selection: selection)
    }

    /// Asks for access to Apple Books, then reads the books.
    ///
    /// - Returns: A message if access wasn't given.
    func allowAccess() async -> String? {
        let problem = access.allow()
        await load()
        return problem
    }
}
