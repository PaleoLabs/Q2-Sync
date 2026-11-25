//
//  Q2SyncApp.swift
//  Q2-Sync › App
//
//  PURPOSE
//  The app's entry point. `@main` tells Swift that this type starts the
//  program; SwiftUI then creates the scenes declared in `body`:
//    • the main window (a single window, like Music or Finder),
//    • the menu bar item (always shown: with the window closed it's the
//      only way back, since the Dock icon is hidden then),
//    • the Settings window (⌘,),
//    • the help window (⌘?), showing the user guide.
//
//  HOW IT FITS
//  It creates the long-lived models once (`LibraryModel`, `DeviceMonitor`,
//  `SyncCoordinator`, `AutoSyncController`) and hands them to the views.
//  The app keeps running when its window is closed, so it can notice your
//  Q2 connecting; quit it from the menu bar item or with ⌘Q. While the
//  window is closed the Dock icon is hidden (see `DockIconController`).
//

import SwiftUI
import UniformTypeIdentifiers

@main
struct Q2SyncApp: App {

    /// Identifier of the main window, used to reopen it.
    static let mainWindowID = "main"

    /// Identifier of the help window.
    static let helpWindowID = "help"

    // `@State` makes SwiftUI create each model once and keep it alive for
    // the app's lifetime (instead of recreating it on every redraw).
    @State private var library: LibraryModel
    @State private var devices: DeviceMonitor
    @State private var sync: SyncCoordinator
    @State private var autoSync: AutoSyncController

    /// Connects an old-style AppKit "app delegate" so we can tell macOS to
    /// keep the app running after its window closes (SwiftUI quits a
    /// single-window app by default). `@NSApplicationDelegateAdaptor`
    /// creates the delegate and hands it to AppKit.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Creates the models. They depend on each other, so they're built
    /// here in order rather than as separate property initial values.
    init() {
        let library = LibraryModel()
        let devices = DeviceMonitor()
        let sync = SyncCoordinator()
        _library = State(initialValue: library)
        _devices = State(initialValue: devices)
        _sync = State(initialValue: sync)
        let autoSync = AutoSyncController(library: library, devices: devices, sync: sync)
        _autoSync = State(initialValue: autoSync)
        AppDelegate.cardBusyActivity = { [weak autoSync] in autoSync?.cardBusyActivity }
        // Starts hiding the Dock icon while the main window is closed.
        _ = DockIconController.shared
    }

    var body: some Scene {
        Window("Q2 Sync", id: Self.mainWindowID) {
            RootView(library: library, devices: devices)
                // `.environment` makes these available to any view inside,
                // which reads them with `@Environment`.
                .environment(sync)
                .environment(autoSync)
                .frame(minWidth: 900, minHeight: 560)
                .background(WindowOpenerBridge(controller: autoSync))
        }
        .windowToolbarStyle(.unified)
        .commands {
            DeviceCommands(controller: autoSync)
            SongListCommands(controller: autoSync)
            SongInfoCommands()
            AboutCommand()
            HelpCommand()
        }

        Window("Q2 Sync Help", id: Self.helpWindowID) {
            HelpView()
                .frame(minWidth: 620, minHeight: 400)
        }
        .defaultSize(width: 900, height: 700)
        // Only Help › Q2 Sync Help opens it: not launching the app, and no
        // extra item in the Window menu.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()

        MenuBarExtra {
            MenuBarContent(controller: autoSync)
        } label: {
            MenuBarLabel(controller: autoSync)
        }

        Settings {
            AppSettingsView(devices: devices)
        }
    }
}

/// Replaces "About Q2 Sync" so the panel shows the build number and the git
/// commit it was built from, e.g. "Version 0.1 (142 · 0e7d893)". Both are
/// written into the built Info.plist by `Scripts/stamp-version.sh`.
struct AboutCommand: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Q2 Sync") {
                let info = Bundle.main.infoDictionary
                let build = info?["CFBundleVersion"] as? String ?? "?"
                let commit = info?["Q2SyncBuildCommit"] as? String ?? "unknown"
                NSApp.orderFrontStandardAboutPanel(options: [
                    .version: "\(build) · \(commit)"
                ])
            }
        }
    }
}

/// Help › Q2 Sync Help (⌘?): opens the user guide in its own window.
struct HelpCommand: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Q2 Sync Help") { openWindow(id: Q2SyncApp.helpWindowID) }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}

/// The Device menu in the menu bar.
struct DeviceCommands: Commands {
    let controller: AutoSyncController

    var body: some Commands {
        CommandMenu("Device") {
            let connected = controller.devices.connected
            Button("Sync Now") { Task { await controller.startSync(automatic: false) } }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!controller.canStartCardOperation)
            Button("Install Firmware…") {
                controller.showMainWindow()
                controller.installer.present()
            }
            .disabled(connected?.accessURL == nil || controller.isCardInUse(except: .installer))
            Button("Verify Card…") {
                controller.showMainWindow()
                controller.verifier.present()
            }
            .disabled(connected?.accessURL == nil || controller.isCardInUse(except: .verifier))
            Divider()
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

/// AppKit hooks SwiftUI doesn't offer directly.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Keep running (in the menu bar) after the main window is closed, so
    /// Q2 Sync still notices the Q2 connecting. Quit with ⌘Q or the menu.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Describes what's using the card right now, if anything. Set by
    /// `Q2SyncApp` (the delegate is created by AppKit, so it can't be
    /// handed the controller directly).
    @MainActor static var cardBusyActivity: (@MainActor () -> String?)?

    /// Asks before quitting while something is writing to the card, from
    /// any Quit (⌘Q, the app menu or the menu bar item).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let activity = Self.cardBusyActivity?() else { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Quit Q2 Sync?"
        alert.informativeText = "\(activity). Quitting now stops it part-way; "
            + "anything left unfinished may need to be done again."
        alert.addButton(withTitle: "Don't Quit")
        alert.addButton(withTitle: "Quit Anyway")
        alert.buttons[1].hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}

/// An invisible view that hands SwiftUI's `openWindow` action to the
/// auto-sync controller, so notifications can reopen the main window even
/// before the menu bar icon has appeared.
private struct WindowOpenerBridge: View {
    let controller: AutoSyncController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.onAppear {
            controller.openMainWindow = { openWindow(id: Q2SyncApp.mainWindowID) }
        }
    }
}
