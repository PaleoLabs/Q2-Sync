//
//  FirmwareUpdateSection.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The "Firmware Updates" part of a Q2's Settings tab.
//    • Install Firmware… (Q2 Pod or stock), and the status of firmware put
//      on the card that the Q2 hasn't installed yet.
//    • Q2 Pod: an optional check of GitHub for new releases, your installed
//      version (typed in, as the card doesn't record it), the latest
//      release's notes, a link, Update…, and Dismiss.
//    • Shanling stock: the latest version on Shanling's page, checked only
//      when you ask, with a link and Install….
//  Firmware is only downloaded when you click Install or Update.
//
//  HOW IT FITS
//  Shown inside `DeviceSettingsView`'s Form. Data from `FirmwareModel`;
//  per-device values saved through `DeviceMonitor`.
//

import SwiftUI

/// Firmware update settings and status for one Q2.
struct FirmwareUpdateSection: View {

    let connected: ConnectedDevice
    let devices: DeviceMonitor
    let firmware: FirmwareModel
    let installer: FirmwareInstaller

    /// Whether checking is on (saved in UserDefaults).
    @AppStorage(FirmwareModel.enabledKey) private var checkEnabled = false

    /// The version text being edited; saved when you press Return or leave the field.
    @State private var versionText = ""

    var body: some View {
        Section {
            installContent
            if connected.device.firmware == .q2Pod {
                q2PodContent
            } else {
                stockContent
            }
        } header: {
            Text("Firmware Updates").id(SettingsSection.firmwareUpdates)
        } footer: {
            Text("Firmware is downloaded only when you click Install or Update. Q2 Sync checks it and copies it to the card as update.tar; your Q2 installs it when you choose TF card update.")
        }
        .onAppear { versionText = connected.device.installedFirmwareVersion ?? "" }
        // Follow changes made elsewhere (Mark as Installed, the "Did the
        // update finish?" question), unless it's the user's own typing.
        .onChange(of: connected.device.installedFirmwareVersion) { _, saved in
            let shown = versionText.trimmingCharacters(in: .whitespaces)
            if shown != (saved ?? "") { versionText = saved ?? "" }
        }
    }

    // MARK: Installing

    @ViewBuilder
    private var installContent: some View {
        if let pending = connected.device.pendingFirmwareInstall {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(pending.image.displayName) is on the card, waiting for you to install it on the Q2: \(connected.device.profile.tfCardUpdateMenuPath).",
                      systemImage: "clock.arrow.circlepath")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Mark as Installed") {
                        installer.markPendingInstalled(removeFile: false)
                    }
                    .help("Switch this Q2's settings to \(pending.image.kind.displayName)")
                    Button("Remove from Card") { installer.cancelPending() }
                }
            }
        }
        HStack {
            Text("Switch between Q2 Pod and Shanling's stock firmware, or update.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Install Firmware…") { installer.present() }
                .disabled(connected.accessURL == nil || installer.isBusy)
        }
    }

    // MARK: Q2 Pod

    @ViewBuilder
    private var q2PodContent: some View {
        Toggle("Check GitHub for new Q2 Pod releases", isOn: $checkEnabled)
            .onChange(of: checkEnabled) { _, on in
                if on { Task { await firmware.checkNow() } }
            }

        TextField("Installed version", text: $versionText, prompt: Text("e.g. 1.8.5 (optional)"))
            .onSubmit { devices.setInstalledFirmwareVersion(versionText) }
            .onChange(of: versionText) { _, text in
                // Save as soon as it parses, so the status updates live.
                if text.isEmpty || FirmwareVersion(text) != nil { devices.setInstalledFirmwareVersion(text) }
            }

        if checkEnabled || firmware.wasCheckedOnRequest {
            HStack {
                statusLabel
                Spacer()
                if firmware.isChecking {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Check Now") { Task { await firmware.checkNow() } }
                        .disabled(connected.device.knownFirmware == nil)
                }
            }
            if let error = firmware.errorMessage {
                Text(error).font(.callout).foregroundStyle(.orange)
            }
            if let latest = firmware.latest {
                releaseDetails(latest)
            }
        }
    }

    // MARK: Shanling stock

    @ViewBuilder
    private var stockContent: some View {
        HStack {
            if let version = firmware.latestStockVersion {
                Label("The latest Shanling firmware is V\(version).", systemImage: "sparkles")
                    .foregroundStyle(.blue)
            } else {
                Text("Latest Shanling firmware: not checked yet.").foregroundStyle(.secondary)
            }
            Spacer()
            if firmware.isCheckingStock {
                ProgressView().controlSize(.small)
            } else {
                Button("Check Now") { Task { await firmware.checkStockNow() } }
                    .disabled(connected.device.knownFirmware == nil)
            }
        }
        if let error = firmware.stockErrorMessage {
            Text(error).font(.callout).foregroundStyle(.orange)
        }
        if let version = firmware.latestStockVersion {
            VStack(alignment: .leading, spacing: 8) {
                // Q2 Sync can't see the installed version, so say where it is.
                Text("To see your version: \(connected.device.profile.versionLocationHint)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Link("View Shanling's Download Page", destination: FirmwareSources.stockDownloadPage)
                    Spacer()
                    Button("Install V\(version)…") { installer.present(selecting: .stock) }
                        .disabled(connected.accessURL == nil || installer.isBusy)
                }
            }
        }
    }

    // MARK: Q2 Pod status

    /// One line summarizing the status.
    @ViewBuilder
    private var statusLabel: some View {
        let latestTag = firmware.latest?.tag ?? ""
        switch firmware.status(for: connected.device) {
        case .upToDate?:
            Label("You have the latest Q2 Pod (\(latestTag)).", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .updateAvailable?:
            Label("Q2 Pod \(latestTag) is available.", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
        case .newRelease?:
            Label("The latest Q2 Pod release is \(latestTag).", systemImage: "sparkles")
                .foregroundStyle(.blue)
        case .dismissed?:
            Label("Latest Q2 Pod: \(latestTag) (dismissed).", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case nil:
            Text("Not checked yet.").foregroundStyle(.secondary)
        }
    }

    /// The release's notes (rendered from Markdown), link and Dismiss.
    @ViewBuilder
    private func releaseDetails(_ release: FirmwareRelease) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Q2 Pod \(release.tag)").font(.headline)
                if let date = release.publishedAt {
                    Text(date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                Text(Self.markdown(release.notes))
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 160)
            HStack {
                Link("View Release on GitHub", destination: release.pageURL)
                Spacer()
                if firmware.status(for: connected.device)?.shouldNotify == true {
                    Button("Dismiss") { devices.dismissFirmwareRelease(release.tag) }
                    Button("Update to \(release.tag)…") { installer.present(selecting: .q2Pod) }
                        .disabled(connected.accessURL == nil || installer.isBusy)
                }
            }
        }
    }

    /// Release notes as styled text; falls back to plain text.
    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
