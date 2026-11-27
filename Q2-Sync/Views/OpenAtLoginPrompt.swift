//
//  OpenAtLoginPrompt.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  Opening Q2 Sync at login: the one place it's offered besides the app's
//  Settings window. `LoginItem` wraps Apple's `SMAppService.mainApp` for
//  both; `OpenAtLoginPrompt` is a single line under a Q2's Auto-Sync
//  picker, shown only while auto-sync is on and Q2 Sync doesn't open at
//  login. That's the moment it matters: auto-sync only works while the app
//  is running. Onboarding and Sync Complete never ask.
//
//  HOW IT FITS
//  `DeviceGeneralView` (DeviceView.swift) shows the prompt; the toggle in
//  `AppSettingsView` stays the real control and uses `LoginItem` too.
//

import ServiceManagement
import SwiftUI

/// Opens Q2 Sync at login, through macOS's Login Items.
enum LoginItem {

    /// `true` if Q2 Sync opens at login.
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    /// Turns opening at login on or off.
    ///
    /// - Parameter enabled: The new setting.
    /// - Returns: A note for the user if macOS wants approval or refused,
    ///   else `nil`.
    /// - Side effects: Registers or unregisters the login item.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return SMAppService.mainApp.status == .requiresApproval
                ? "Approve Q2 Sync in System Settings › General › Login Items." : nil
        } catch {
            return "Couldn't change this: \(error.localizedDescription)"
        }
    }
}

/// "Q2 Sync needs to be running to notice your Q2. [Open at Login]",
/// shown while it doesn't open at login.
struct OpenAtLoginPrompt: View {

    /// Read from macOS when shown, and after the button.
    @State private var isOn = LoginItem.isOn

    /// A note if macOS wants approval or refused.
    @State private var message: String?

    var body: some View {
        Group {
            if let message {
                VStack(alignment: .leading, spacing: 6) {
                    Label(message, systemImage: "info.circle")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                }
            } else if !isOn {
                HStack {
                    Label("Q2 Sync needs to be running to notice your Q2.", systemImage: "power")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Open at Login") {
                        message = LoginItem.set(true)
                        isOn = LoginItem.isOn
                    }
                }
            }
        }
        .font(.callout)
        .onAppear { isOn = LoginItem.isOn }
    }
}
