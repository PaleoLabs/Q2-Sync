//
//  BooksAccess.swift
//  Q2-Sync › App
//
//  PURPOSE
//  Permission to read Apple Books' audiobooks. The folder is inside Apple
//  Books' own container, which the sandbox can't read until the user picks
//  it once in an Open panel (Allow Access to Books). It's then remembered
//  with a read-only security-scoped bookmark in UserDefaults, and keeps
//  working after relaunches and rebuilds (tested for issue #48).
//
//  SAFETY
//  The bookmark is read-only, so nothing can be written to Apple Books
//  even by mistake. Only Apple Books' own "Books" folder is accepted: any
//  other folder is refused, as audiobooks come only from Apple Books.
//
//  HOW IT FITS
//  Owned by `AutoSyncController`, one for all Q2s. The Audiobooks tab shows
//  `status` and calls `allow()`; the audiobook reader uses `folder`.
//

import AppKit
import Foundation
import Observation

/// Whether Q2 Sync may read Apple Books' audiobooks.
@MainActor
@Observable
final class BooksAccess {

    /// Where things stand.
    enum Status: Equatable {
        /// Never allowed (or forgotten): the Allow button is shown.
        case notAllowed
        /// Allowed and reachable: `folder` is set.
        case allowed
        /// Allowed once, but the permission no longer works.
        case unavailable(String)
    }

    /// UserDefaults key for the Books folder's bookmark.
    static let bookmarkKey = "appleBooksFolderBookmark"

    private(set) var status: Status = .notAllowed

    /// The Books folder, with access started, while `status` is `.allowed`.
    private(set) var folder: URL?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Resolves the saved bookmark and starts access to the folder.
    func load() {
        stopAccess()
        guard let bookmark = defaults.data(forKey: Self.bookmarkKey) else {
            status = .notAllowed
            return
        }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                                 bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource() else {
            status = .unavailable("Q2 Sync can no longer read Apple Books. Allow access again.")
            return
        }
        folder = url
        status = .allowed
        if isStale, let fresh = try? url.bookmarkData(options: Self.bookmarkOptions) {
            defaults.set(fresh, forKey: Self.bookmarkKey)
        }
    }

    /// Asks for Apple Books' folder in an Open panel and remembers it.
    ///
    /// - Returns: A message if the folder was refused or couldn't be saved,
    ///   `nil` if allowed or cancelled.
    @discardableResult
    func allow() -> String? {
        let expected = AppleBooksSource.defaultFolder
        let panel = NSOpenPanel()
        panel.message = "To sync audiobooks, allow Q2 Sync to read Apple Books' “Books” folder. It's already selected: click Allow Access. Q2 Sync only reads it."
        panel.prompt = "Allow Access"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = expected
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        let picked = PathGuard.realPath(url.path) ?? url.standardizedFileURL.path
        let wanted = PathGuard.realPath(expected.path) ?? expected.standardizedFileURL.path
        guard picked == wanted else {
            return "That isn't Apple Books' folder. Click Allow Access to Books again and choose the “Books” folder it opens at."
        }
        do {
            defaults.set(try url.bookmarkData(options: Self.bookmarkOptions), forKey: Self.bookmarkKey)
        } catch {
            return "Couldn't remember access to Apple Books: \(error.localizedDescription)"
        }
        load()
        return nil
    }

    /// Forgets the permission (the Allow button comes back).
    func forget() {
        defaults.removeObject(forKey: Self.bookmarkKey)
        load()
    }

    /// Read-only: Q2 Sync never writes to Apple Books.
    private static let bookmarkOptions: URL.BookmarkCreationOptions = [
        .withSecurityScope, .securityScopeAllowOnlyReadAccess,
    ]

    private func stopAccess() {
        folder?.stopAccessingSecurityScopedResource()
        folder = nil
    }
}
