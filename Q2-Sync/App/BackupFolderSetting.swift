//
//  BackupFolderSetting.swift
//  Q2-Sync › App
//
//  PURPOSE
//  Where Q2 Pod data backups go. The default is ~/Downloads/Q2 Sync
//  Backups (the sandbox's Downloads entitlement covers it). The user can
//  choose any other folder in an Open panel; it's remembered with a
//  security-scoped bookmark (read-write) in UserDefaults, and Use Default
//  goes back. One folder for all Q2s.
//
//  SAFETY
//  A chosen folder inside ~/Music, or on a Q2's card, is refused here, and
//  `PodDataBackup.backUp` still refuses any write outside the folder or in
//  a protected one. If a chosen folder can't be reached (e.g. its drive is
//  unplugged), backups stop with a message rather than going elsewhere.
//
//  HOW IT FITS
//  Owned by `PodDataModel`; shown and changed in `PodDataSection`.
//

import AppKit
import Foundation
import Observation

/// The folder Q2 Pod data backups go into.
@MainActor
@Observable
final class BackupFolderSetting {

    /// UserDefaults key for the chosen folder's bookmark (absent: default).
    static let bookmarkKey = "podBackupsFolderBookmark"

    /// The folder backups go into, or `nil` if a chosen folder can't be
    /// reached right now (see `problem`).
    private(set) var folder: URL?

    /// `true` if the user chose a folder (not the default).
    private(set) var isCustom = false

    /// Why the chosen folder can't be used, if it can't.
    private(set) var problem: String?

    /// The chosen folder whose security-scoped access we hold.
    private var accessedURL: URL?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// e.g. "Downloads › Q2 Sync Backups", or a full path outside home.
    var displayName: String {
        guard let folder else { return "Unavailable" }
        let home = PathGuard.realHomeDirectory.standardizedFileURL.path
        let path = folder.standardizedFileURL.path
        guard path.hasPrefix(home + "/") else { return path }
        return path.dropFirst(home.count + 1).split(separator: "/").joined(separator: " › ")
    }

    /// Resolves the saved folder (or the default) and starts access to it.
    func load() {
        stopAccess()
        problem = nil
        guard let bookmark = defaults.data(forKey: Self.bookmarkKey) else {
            isCustom = false
            folder = PodDataBackup.backupsFolder
            return
        }
        isCustom = true
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                                 bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource() else {
            folder = nil
            problem = "The backup folder you chose can't be reached (is its drive connected?). Choose it again, or use the default."
            return
        }
        accessedURL = url
        folder = url
        if isStale, let fresh = try? url.bookmarkData(options: [.withSecurityScope]) {
            defaults.set(fresh, forKey: Self.bookmarkKey)
        }
    }

    /// Asks for a folder in an Open panel and remembers it.
    ///
    /// - Parameter cardRoots: Mounted Q2 cards; a folder on one is refused.
    /// - Returns: A message if the folder was refused or couldn't be saved.
    @discardableResult
    func choose(refusingCards cardRoots: [URL]) -> String? {
        let panel = NSOpenPanel()
        panel.message = "Choose a folder for Q2 Pod data backups."
        panel.prompt = "Use This Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder ?? PodDataBackup.backupsFolder
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        if let reason = Self.refusal(for: url, cardRoots: cardRoots) { return reason }
        do {
            defaults.set(try url.bookmarkData(options: [.withSecurityScope]), forKey: Self.bookmarkKey)
        } catch {
            return "Couldn't remember this folder: \(error.localizedDescription)"
        }
        load()
        return nil
    }

    /// Goes back to ~/Downloads/Q2 Sync Backups.
    func useDefault() {
        defaults.removeObject(forKey: Self.bookmarkKey)
        load()
    }

    /// Why a folder can't hold backups, or `nil` if it can.
    private static func refusal(for url: URL, cardRoots: [URL]) -> String? {
        guard let path = PathGuard.realPath(url.path) else { return "That folder can't be used." }
        let music = PathGuard.realPath(PathGuard.defaultHomeMusicFolder.path) ?? PathGuard.defaultHomeMusicFolder.path
        if path == music || PathGuard.isInside(path, folder: music) {
            return "Backups can't go in your Music folder. Choose another folder."
        }
        for card in cardRoots {
            let root = PathGuard.realPath(card.path) ?? card.standardizedFileURL.path
            if path == root || PathGuard.isInside(path, folder: root) {
                return "Backups protect against losing the card, so they can't go on it. Choose a folder on your Mac."
            }
        }
        return nil
    }

    /// Releases access to the previously chosen folder.
    private func stopAccess() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }
}
