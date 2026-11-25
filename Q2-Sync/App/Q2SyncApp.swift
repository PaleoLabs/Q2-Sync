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
        AppDelegate.controller = autoSync
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
                // Wide enough for the library view with the sidebar and
                // Song Info at their widest (see `LibraryCategoryView`).
                .frame(minWidth: 1100, minHeight: 560)
                .background(WindowOpenerBridge(controller: autoSync))
        }
        .windowToolbarStyle(.unified)
        // Window › Q2 Sync: brings the window back.
        .keyboardShortcut("0", modifiers: .command)
        .commands {
            LibraryCommands(controller: autoSync)
            FindCommands(controller: autoSync)
            NavigationCommands(controller: autoSync)
            DeviceCommands(controller: autoSync)
            SongListCommands(controller: autoSync)
            SongInfoCommands()
            AboutCommand()
            UpdateCommand(controller: autoSync)
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

/// AppKit hooks SwiftUI doesn't offer directly.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Keep running (in the menu bar) after the main window is closed, so
    /// Q2 Sync still notices the Q2 connecting. Quit with ⌘Q or the menu.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// For the Dock menu and the Quit warning. Set by `Q2SyncApp` (the
    /// delegate is created by AppKit, so it can't be handed the controller
    /// directly).
    @MainActor static weak var controller: AutoSyncController?

    /// Adds Sync Now and Eject to the Dock icon's menu, above macOS's own
    /// items. Built each time the menu opens, so it's up to date. Enabled
    /// by the same rules as the menu bar item's.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let controller = Self.controller else { return nil }
        let connected = controller.devices.connected
        let menu = NSMenu()
        // `isEnabled` is set here, not worked out by AppKit.
        menu.autoenablesItems = false

        let sync = NSMenuItem(title: "Sync Now", action: #selector(syncFromDock), keyEquivalent: "")
        sync.target = self
        sync.isEnabled = controller.canStartCardOperation
        menu.addItem(sync)

        let title = connected.map { "Eject “\($0.device.name)”" } ?? "Eject"
        let eject = NSMenuItem(title: title, action: #selector(ejectFromDock), keyEquivalent: "")
        eject.target = self
        eject.isEnabled = connected != nil && !controller.isCardBusy && !controller.devices.isEjecting
        menu.addItem(eject)
        return menu
    }

    @objc private func syncFromDock() {
        Task { await Self.controller?.startSync(automatic: false) }
    }

    @objc private func ejectFromDock() {
        Task { await Self.controller?.eject() }
    }

    /// Asks before quitting while something is writing to the card, from
    /// any Quit (⌘Q, the app menu, the Dock or the menu bar item).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let activity = Self.controller?.cardBusyActivity else { return .terminateNow }
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
