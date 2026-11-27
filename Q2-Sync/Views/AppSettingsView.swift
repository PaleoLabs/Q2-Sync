//
//  AppSettingsView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The app's Settings window (Q2 Sync › Settings…, or ⌘,): open Q2 Sync
//  at login so auto-sync works without opening the app yourself, turn the
//  automatic check for new versions off or on, and bring back messages you
//  turned off. The login toggle is the real control; the
//  only other place that offers it is `OpenAtLoginPrompt`, under a Q2's
//  Auto-Sync picker.
//
//  HOW IT FITS
//  Declared as the `Settings` scene in `Q2SyncApp`. Per-card settings
//  (firmware, "When This Q2 Connects") live on that card's General tab.
//
//  LOGIN ITEMS (explained)
//  `SMAppService.mainApp` is Apple's API for "open this app at login". It
//  shows up in System Settings › General › Login Items, where you can
//  also turn it off. macOS may ask you to approve it there.
//

import ServiceManagement
import SwiftUI

/// The Settings window.
struct AppSettingsView: View {

    /// For forgetting drives marked "Not My Q2".
    let devices: DeviceMonitor

    /// Whether closing the main window shows the menu bar tip. Turned off by
    /// the tip's "Don't show again"; "Show Menu Bar Tip Again" turns it back
    /// on. `@AppStorage` reads and writes UserDefaults and redraws the view
    /// when it changes.
    @AppStorage(DockIconController.closeNoticeKey) private var showCloseNotice = true

    /// Whether Q2 Sync looks for a newer version by itself.
    @AppStorage(AppUpdateModel.automaticKey) private var checksForUpdates = true

    /// Whether Q2 Sync opens at login (read from macOS).
    @State private var opensAtLogin = LoginItem.isOn

    /// A problem changing the login item, if any.
    @State private var loginItemMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open Q2 Sync at login", isOn: Binding(
                    get: { opensAtLogin },
                    set: { setOpensAtLogin($0) }))
                if let loginItemMessage {
                    Text(loginItemMessage).font(.callout).foregroundStyle(.orange)
                    Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                }
            } footer: {
                Text("Keeps Q2 Sync in the menu bar, ready for your Q2.")
            }

            Section {
                Toggle("Check for new versions automatically", isOn: $checksForUpdates)
            } footer: {
                Text("Asks GitHub when Q2 Sync starts, then once a day. Nothing about you is sent.")
            }

            // Bring back questions and tips you turned off.
            Section("Messages") {
                Button("Show Menu Bar Tip Again") { showCloseNotice = true }
                    .disabled(showCloseNotice)
                Button("Ask Again About “Not My Q2” Drives") { devices.clearIgnoredDrives() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }

    /// Registers or unregisters the login item.
    private func setOpensAtLogin(_ enabled: Bool) {
        loginItemMessage = LoginItem.set(enabled)
        opensAtLogin = LoginItem.isOn
    }
}
