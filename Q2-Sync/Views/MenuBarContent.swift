//
//  MenuBarContent.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The Q2 Sync menu in the menu bar: shows whether the Q2 is connected
//  and any sync in progress, with Sync Now, Eject, Open Q2 Sync, Settings,
//  Help, About and Quit.
//
//  HOW IT FITS
//  Declared as a `MenuBarExtra` scene in `Q2SyncApp`. Always shown.
//  Actions go through `AutoSyncController` and `DeviceMonitor`.
//

import SwiftUI

/// The menu shown from the menu bar icon.
struct MenuBarContent: View {

    let controller: AutoSyncController
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let devices = controller.devices
        let sync = controller.sync

        if let connected = devices.connected {
            Text("“\(connected.device.name)” connected")
            if sync.phase == .running {
                Text("Syncing… \(Int(sync.progress.fractionComplete * 100))%")
            }
            Button("Sync Now") { Task { await controller.startSync(automatic: false) } }
                .disabled(!controller.canStartCardOperation)
            Button("Eject “\(connected.device.name)”") { Task { await controller.eject() } }
                .disabled(controller.isCardBusy || devices.isEjecting)
        } else {
            Text("No Q2 connected")
        }

        Divider()
        Button("Open Q2 Sync") { controller.showMainWindow() }
        Button("Settings…") {
            // Without a Dock icon, Settings would open out of sight.
            DockIconController.shared.openSettings { openSettings() }
        }
        .keyboardShortcut(",")
        Button("Q2 Sync Help") {
            DockIconController.shared.openHelp { openWindow(id: Q2SyncApp.helpWindowID) }
        }
        Button("About Q2 Sync") { AboutCommand.showAboutPanel() }
        Divider()
        Button("Quit Q2 Sync") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// The menu bar icon. It also hands SwiftUI's `openWindow` action to the
/// controller, so notifications can reopen the main window after it was
/// closed. (Only views can read `openWindow` from the environment.)
struct MenuBarLabel: View {

    let controller: AutoSyncController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: controller.sync.phase == .running ? "arrow.triangle.2.circlepath"
                                                             : DockIconController.menuBarSymbol)
            .onAppear {
                controller.openMainWindow = { openWindow(id: Q2SyncApp.mainWindowID) }
            }
    }
}
