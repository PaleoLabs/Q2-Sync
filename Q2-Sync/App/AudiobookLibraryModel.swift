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
        do {
            state = .loaded(try await source.loadAudiobooks())
        } catch AudiobookError.noBooksList {
            state = .loaded([])
        } catch {
            state = .failed(error.localizedDescription)
        }
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
