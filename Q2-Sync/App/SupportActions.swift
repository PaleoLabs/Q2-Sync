//
//  SupportActions.swift
//  Q2-Sync › App
//
//  PURPOSE
//  The small "open something elsewhere" actions used by menus and buttons:
//  the sync logs, the release notes, a new version's download page,
//  reporting a problem, and showing the card in Finder.
//
//  PRIVACY
//  The web links are fixed addresses. Nothing about you, your Mac, your
//  library or your Q2 is put in them.
//

import AppKit

/// Actions that hand something to Finder or the web browser.
@MainActor
enum SupportActions {

    /// Help › Release Notes.
    static let releaseNotes = URL(string: "https://github.com/PaleoLabs/Q2-Sync/releases")!

    /// Help › Report a Problem…: an empty new issue.
    static let newIssue = URL(string: "https://github.com/PaleoLabs/Q2-Sync/issues/new")!

    /// Opens the latest release's page, to download a new version.
    static func showLatestRelease() {
        NSWorkspace.shared.open(AppUpdateChecker.downloadPage)
    }

    /// Opens the folder of sync logs in Finder, creating it if needed.
    static func showSyncLogs() {
        let folder = SyncLog.logsDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    /// Opens the card in a Finder window.
    static func showCardInFinder(_ connected: ConnectedDevice) {
        let url = connected.accessURL ?? connected.volume.url
        // If macOS won't open the folder, select it in Finder instead.
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
