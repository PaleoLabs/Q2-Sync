//
//  AppCommands.swift
//  Q2-Sync › App
//
//  PURPOSE
//  The menu bar menus: what Q2 Sync adds to the app, File, Edit, View,
//  Device and Help menus, with their keyboard shortcuts.
//
//  HOW IT FITS
//  `Q2SyncApp` lists these with `.commands`. Navigation goes through
//  `AppNavigation`, card actions through `AutoSyncController`. A new or
//  changed shortcut also goes in the user guide's "Keyboard shortcuts".
//

import SwiftUI
import UniformTypeIdentifiers

/// Replaces "About Q2 Sync" so the panel shows the build number and the git
/// commit it was built from, e.g. "Version 0.1 (142 · 0e7d893)", with links
/// to the project and its license. The number and commit are written into
/// the built Info.plist by `Scripts/stamp-version.sh`.
struct AboutCommand: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Q2 Sync") { Self.showAboutPanel() }
        }
    }

    /// Shows the About panel, from the app menu or the menu bar item.
    @MainActor static func showAboutPanel() {
        let info = Bundle.main.infoDictionary
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let commit = info?["Q2SyncBuildCommit"] as? String ?? "unknown"
        DockIconController.shared.showAboutPanel(options: [
            .version: "\(build) · \(commit)",
            .credits: credits,
        ])
    }

    /// The links under the version, one per line.
    @MainActor private static var credits: NSAttributedString {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.paragraphSpacing = 4
        let plain: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: centered,
        ]
        let links = [
            ("Q2 Sync on GitHub", SupportActions.project),
            ("GNU General Public License v3.0", SupportActions.license),
        ]
        let text = NSMutableAttributedString()
        for (title, url) in links {
            if text.length > 0 { text.append(NSAttributedString(string: "\n", attributes: plain)) }
            let link = plain.merging([.link: url]) { $1 }
            text.append(NSAttributedString(string: title, attributes: link))
        }
        return text
    }
}

/// Q2 Sync › Check for Updates…, under About: looks for a newer release.
struct UpdateCommand: Commands {
    let controller: AutoSyncController

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Task { await controller.updates.checkOnRequest() } }
                .disabled(controller.updates.isCheckingOnRequest)
        }
    }
}

/// The Help menu: the user guide (⌘?), sync logs, and links to GitHub.
struct HelpCommand: Commands {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Q2 Sync Help") { openWindow(id: Q2SyncApp.helpWindowID) }
                .keyboardShortcut("?", modifiers: .command)
            Divider()
            Button("Show Sync Logs") { SupportActions.showSyncLogs() }
            Button("Release Notes") { openURL(SupportActions.releaseNotes) }
            Button("Report a Problem…") { openURL(SupportActions.newIssue) }
        }
    }
}

/// File › Refresh Music Library (⌘R) and Show in Finder (⇧⌘R).
struct LibraryCommands: Commands {
    let controller: AutoSyncController

    // Nothing reads the library before the first-launch notice is accepted.
    @AppStorage(FirstLaunchNoticeView.acknowledgedKey) private var noticeAcknowledged = false

    var body: some Commands {
        CommandGroup(after: .newItem) {
            let navigation = controller.navigation
            Button("Refresh Music Library") { Task { await controller.library.load() } }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!noticeAcknowledged || controller.library.state == .loading)
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(navigation.selectedSongFiles)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!navigation.isMainWindowFront || navigation.selectedSongFiles.isEmpty
                      || controller.isShowingSheet)
        }
    }
}

/// Edit › Find (⌘F): puts the cursor in the search or filter field on
/// screen (the library browser, the Q2's Music tab or the sync preview).
/// Dimmed where there's none.
struct FindCommands: Commands {
    let controller: AutoSyncController

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find") { controller.navigation.find() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!available)
        }
    }

    private var available: Bool {
        let navigation = controller.navigation
        guard navigation.isMainWindowFront, let field = navigation.filterField else { return false }
        // Under another sheet, the window's own fields can't be reached.
        return field == .syncPreview || !controller.isShowingSheet
    }
}

/// View: the library lists (⌘1–⌘4) and the Q2's page (⌘5).
struct NavigationCommands: Commands {
    let controller: AutoSyncController

    @AppStorage(FirstLaunchNoticeView.acknowledgedKey) private var noticeAcknowledged = false

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            let unavailable = !noticeAcknowledged || !controller.navigation.isMainWindowFront
                || controller.isShowingSheet
            let connected = controller.devices.connected
            ForEach(Array(BrowseCategory.allCases.enumerated()), id: \.element) { index, category in
                Button(category.rawValue) { controller.show(.library(category)) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .disabled(unavailable)
            }
            Divider()
            // With no Q2, this is the "Connect Your Q2" page.
            Button("Show Q2") { controller.showQ2() }
                .keyboardShortcut("5", modifiers: .command)
                .disabled(unavailable)
            Button("Show Q2 Music") { controller.showQ2(tab: .music) }
                .disabled(unavailable || connected == nil)
            Button("Show Q2 Settings") { controller.showQ2(tab: .settings) }
                .disabled(unavailable || connected == nil)
            Divider()
        }
    }
}

/// The Device menu in the menu bar.
struct DeviceCommands: Commands {
    let controller: AutoSyncController
    @AppStorage(FirstLaunchNoticeView.acknowledgedKey) private var noticeAcknowledged = false

    var body: some Commands {
        CommandMenu("Device") {
            let connected = controller.devices.connected
            let podData = controller.podData
            // The same rules as the Settings tab's Q2 Pod Data buttons, and
            // not while a sheet is open over them.
            let podDataUnavailable = !noticeAcknowledged || connected?.accessURL == nil || podData.isBusy
                || controller.isCardInUse(except: .podData) || controller.isShowingSheet

            Button("Sync Now") { Task { await controller.startSync(automatic: false) } }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!controller.canStartCardOperation)
            Divider()
            Button("Install Firmware…") {
                controller.showMainWindow()
                controller.installer.present()
            }
            .disabled(connected?.accessURL == nil || controller.isCardInUse(except: .installer))
            // Dimmed until it's known which firmware the Q2 runs.
            let firmwareKind = connected?.device.knownFirmware
            let canCheck = firmwareKind.map { !controller.firmware.isChecking($0) } ?? false
            Button("Check for Firmware Updates") { controller.checkForFirmwareUpdates() }
                .disabled(!noticeAcknowledged || !canCheck || controller.isShowingSheet)
            Divider()
            Button("Verify Card…") {
                controller.showMainWindow()
                controller.verifier.present()
            }
            .disabled(connected?.accessURL == nil || controller.isCardInUse(except: .verifier))
            Button("Back Up Q2 Pod Data") { controller.backUpPodData() }
                .disabled(podDataUnavailable || podData.backupFolder.folder == nil)
            Button("Restore Q2 Pod Data…") { controller.restorePodData() }
                .disabled(podDataUnavailable)
            Divider()
            Button("Show Card in Finder") {
                if let connected { SupportActions.showCardInFinder(connected) }
            }
            .disabled(connected == nil || controller.devices.isEjecting)
            Button("Eject") { Task { await controller.eject() } }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(connected == nil || controller.devices.isEjecting || controller.isCardBusy)
        }
    }
}

/// View › Show Song Info (⌘I): shows or hides the panel with the selected
/// song's details. Dimmed unless the main window is on a library view.
struct SongInfoCommands: Commands {
    // The same stored setting the library view's panel and toolbar use.
    @AppStorage("showSongInfo") private var showSongInfo = false

    /// Set by `LibraryCategoryView` while it's in the frontmost window.
    @FocusedValue(\.offersSongInfo) private var offersSongInfo

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            let available = offersSongInfo == true
            Button(available && showSongInfo ? "Hide Song Info" : "Show Song Info") {
                showSongInfo.toggle()
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(!available)
        }
    }
}

/// File › Export Song List…: saves a CSV (for Excel or Numbers) of the
/// songs on the Q2 or chosen for the next sync. A menu item only, so the
/// window stays uncluttered.
struct SongListCommands: Commands {
    let controller: AutoSyncController

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export Song List…") { export() }
                .disabled(controller.library.snapshot == nil || controller.devices.referenceContents == nil)
        }
    }

    /// Asks where to save, then writes the CSV.
    ///
    /// - Side effects: Writes one file where the user chooses. Shows an
    ///   alert if that fails.
    @MainActor private func export() {
        guard let snapshot = controller.library.snapshot,
              let reference = controller.devices.referenceContents else { return }
        let marks = LibraryMarks(snapshot: snapshot, record: reference.record,
                                 selection: reference.device.effectiveSelection)
        let text = SongListCSV.make(snapshot: snapshot, marks: marks)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(reference.device.name) songs.csv"
        panel.message = "Songs on your Q2, and those chosen for the next sync."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
