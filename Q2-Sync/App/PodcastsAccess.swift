//
//  PodcastsAccess.swift
//  Q2-Sync › App
//
//  PURPOSE
//  Permission to read the Podcasts app's downloaded episodes. They live in
//  the Podcasts app's group container, which the sandbox can't read until
//  the user picks it once in an Open panel (Allow Access to Podcasts). It's
//  then remembered with a read-only security-scoped bookmark in
//  UserDefaults, and keeps working after relaunches (tested for issue #20).
//
//  SAFETY
//  The bookmark is read-only, so nothing can be written to the Podcasts app
//  (its database syncs with iCloud) even by mistake. Only the Podcasts
//  app's own group container is accepted: any other folder is refused.
//
//  HOW IT FITS
//  Owned by `AutoSyncController`, one for all Q2s, like `BooksAccess`. The
//  Podcasts tab shows `status` and calls `allow()`; the podcast reader uses
//  `folder`.
//

import AppKit
import Foundation
import Observation

/// Whether Q2 Sync may read the Podcasts app's episodes.
@MainActor
@Observable
final class PodcastsAccess {

    /// Where things stand.
    enum Status: Equatable {
        /// Never allowed (or forgotten): the Allow button is shown.
        case notAllowed
        /// Allowed and reachable: `folder` is set.
        case allowed
        /// Allowed once, but the permission no longer works.
        case unavailable(String)
    }

    /// UserDefaults key for the Podcasts folder's bookmark.
    static let bookmarkKey = "applePodcastsFolderBookmark"

    private(set) var status: Status = .notAllowed

    /// The Podcasts folder, with access started, while `status` is `.allowed`.
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
            status = .unavailable("Q2 Sync can no longer read the Podcasts app. Allow access again.")
            return
        }
        folder = url
        status = .allowed
        if isStale, let fresh = try? url.bookmarkData(options: Self.bookmarkOptions) {
            defaults.set(fresh, forKey: Self.bookmarkKey)
        }
    }

    /// Asks for the Podcasts app's folder in an Open panel and remembers it.
    ///
    /// - Returns: A message if the folder was refused or couldn't be saved,
    ///   `nil` if allowed or cancelled.
    @discardableResult
    func allow() -> String? {
        let expected = ApplePodcastsSource.defaultFolder
        let panel = NSOpenPanel()
        panel.message = "To sync podcasts, allow Q2 Sync to read the Podcasts app's folder. It's already selected: click Allow Access. Q2 Sync only reads it."
        panel.prompt = "Allow Access"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = false
        panel.directoryURL = expected
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        let picked = PathGuard.realPath(url.path) ?? url.standardizedFileURL.path
        let wanted = PathGuard.realPath(expected.path) ?? expected.standardizedFileURL.path
        guard picked == wanted else {
            return "That isn't the Podcasts app's folder. Click Allow Access to Podcasts again and choose the folder it opens at."
        }
        do {
            defaults.set(try url.bookmarkData(options: Self.bookmarkOptions), forKey: Self.bookmarkKey)
        } catch {
            return "Couldn't remember access to the Podcasts app: \(error.localizedDescription)"
        }
        load()
        return nil
    }

    /// Forgets the permission (the Allow button comes back).
    func forget() {
        defaults.removeObject(forKey: Self.bookmarkKey)
        load()
    }

    /// Read-only: Q2 Sync never writes to the Podcasts app.
    private static let bookmarkOptions: URL.BookmarkCreationOptions = [
        .withSecurityScope, .securityScopeAllowOnlyReadAccess,
    ]

    private func stopAccess() {
        folder?.stopAccessingSecurityScopedResource()
        folder = nil
    }
}
