//
//  FirmwareInstallSheet.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The "Install Firmware" sheet, in three steps:
//    1. Choose Q2 Pod or Shanling stock (with the latest version of each).
//    2. Progress: downloading, checking, copying to the card.
//    3. What to do on the Q2: eject, TF card update, wait for the restart.
//  If a download can't be found or fails, it offers the download page and
//  "Choose File…" (or drop the zip / update.tar onto the sheet).
//
//  HOW IT FITS
//  Presented by `RootView` when `FirmwareInstaller.isPresentingSheet`.
//  Opened from the General tab and the Device menu.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Installs firmware onto the Q2's card.
struct FirmwareInstallSheet: View {

    let installer: FirmwareInstaller
    let devices: DeviceMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Install Firmware").font(.title2.bold())
                    if let connected = devices.connected {
                        Text("“\(connected.device.name)” runs \(connected.device.firmware.displayName) now.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            switch installer.step {
            case .choosing: choosing
            case .working(let title, let fraction): working(title, fraction: fraction)
            case .placed(let image): placed(image)
            case .failed(let message): failed(message)
            }
        }
        .padding(24)
        .frame(width: 520)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, !installer.isBusy, devices.connected != nil else { return false }
            installer.install(file: url)
            return true
        }
        .interactiveDismissDisabled(installer.isBusy)
    }

    // MARK: Step 1

    @ViewBuilder
    private var choosing: some View {
        Picker("Firmware", selection: Binding(get: { installer.target }, set: { installer.target = $0 })) {
            ForEach(FirmwareKind.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                offerSummary
                Text(description(of: installer.target))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }

        Label("Q2 Sync downloads the firmware, checks it's genuine Q2 firmware, and copies it to the card as update.tar. Your Q2 then installs it when you choose TF card update. Your music isn't touched.",
              systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        HStack {
            Button("Choose File…") { chooseFile() }
                .help("Use a firmware zip or update.tar you downloaded yourself")
            Spacer()
            Button("Cancel") { installer.close() }
                .keyboardShortcut(.cancelAction)
            Button("Download and Copy to Card") { installer.installSelected() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canInstall)
        }
    }

    /// The version line for the selected firmware.
    @ViewBuilder
    private var offerSummary: some View {
        switch installer.offers[installer.target] {
        case .ready(let offer)?:
            HStack {
                Text(offer.displayName).font(.headline)
                Spacer()
                Link(offer.kind == .q2Pod ? "Release Notes" : "Shanling's Page", destination: offer.infoPage)
            }
        case .unavailable(let message)?:
            VStack(alignment: .leading, spacing: 6) {
                Label("Couldn't find the download. \(message)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                manualHelp
            }
        case .loading?, nil:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking up the latest version…").foregroundStyle(.secondary)
            }
        }
    }

    private func description(of kind: FirmwareKind) -> String {
        switch kind {
        case .q2Pod:
            return "DiamondBond's custom firmware: an iPod-style interface, Cover Flow, Rockbox and more. From GitHub; the download must match GitHub's checksum."
        case .stock:
            return "Shanling's own firmware, from Shanling's download page. Use it to go back to stock."
        }
    }

    private var canInstall: Bool {
        guard case .ready? = installer.offers[installer.target] else { return false }
        return devices.connected?.accessURL != nil
    }

    // MARK: Step 2

    @ViewBuilder
    private func working(_ title: String, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            if let fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            Text("Keep the card connected.").font(.callout).foregroundStyle(.secondary)
        }
        HStack {
            Spacer()
            Button("Cancel") { installer.cancel() }
                .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: Step 3

    @ViewBuilder
    private func placed(_ image: FirmwareImageInfo) -> some View {
        let connection = devices.connected?.connection ?? .unknown
        let menu = devices.connected?.device.profile.tfCardUpdateMenuPath
            ?? DeviceProfile.q2Pod.tfCardUpdateMenuPath

        Label("\(image.displayName) is on the card, ready to install.", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .font(.headline)

        NumberedSteps(steps: [
            connection.ejectStep,
            "Make sure the Q2 is well charged (the update checks the battery first).",
            "On the Q2, choose \(menu), and confirm.",
            "Leave the card in and don't turn the Q2 off until it restarts by itself.",
            "Next time you connect the Q2, Q2 Sync will ask whether the update finished, and switch its settings to \(image.kind.displayName).",
        ])

        Link("If the Q2 won't start up afterwards…", destination: FirmwareSources.recoveryHelpPage)
            .font(.callout)

        HStack {
            Spacer()
            Button("Done") { installer.close() }
            Button("Eject Now") {
                installer.close()
                Task { await devices.eject() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(devices.connected == nil || devices.isEjecting)
        }
    }

    // MARK: Failure

    @ViewBuilder
    private func failed(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        Text("Nothing was put on the card.").font(.callout).foregroundStyle(.secondary)
        manualHelp
        HStack {
            Button("Choose File…") { chooseFile() }
            Spacer()
            Button("Close") { installer.close() }
                .keyboardShortcut(.cancelAction)
            Button("Try Again") { installer.startOver() }
                .keyboardShortcut(.defaultAction)
        }
    }

    /// How to fetch the file yourself.
    private var manualHelp: some View {
        let page = installer.target == .q2Pod ? FirmwareSources.q2PodReleasesPage : FirmwareSources.stockDownloadPage
        return VStack(alignment: .leading, spacing: 4) {
            Text("You can download it yourself, then click Choose File… or drop the zip or update.tar here. Q2 Sync checks it the same way.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Link(installer.target == .q2Pod ? "Open Q2 Pod's Releases on GitHub" : "Open Shanling's Download Page",
                 destination: page)
                .font(.callout)
        }
    }

    /// Lets the user pick a firmware zip or update.tar.
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.message = "Choose \(installer.target.displayName) firmware: the zip you downloaded, or update.tar."
        panel.prompt = "Use This File"
        panel.allowedContentTypes = [.zip, UTType(filenameExtension: "tar") ?? .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        installer.install(file: url)
    }
}

/// "Did the firmware update finish?", asked the next time the card
/// connects after firmware was put on it.
struct FirmwareFinishedSheet: View {

    let installer: FirmwareInstaller
    let devices: DeviceMonitor

    /// Whether to remove the leftover update.tar.
    @State private var removeFile = true

    var body: some View {
        if let connected = devices.connected, let pending = connected.device.pendingFirmwareInstall {
            let image = pending.image
            let fileSize = installer.firmwareFileOnCard()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "cpu").font(.system(size: 32)).foregroundStyle(.tint)
                    Text("Did the Firmware Update Finish?").font(.title2.bold())
                }
                Text("Q2 Sync put \(image.displayName) on “\(connected.device.name)” on \(pending.placedAt.formatted(date: .abbreviated, time: .shortened)). If you ran TF card update and the Q2 restarted, it now runs \(image.displayName).")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Not sure? \(image.kind.profile.versionLocationHint)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let fileSize {
                    Toggle("Remove update.tar from the card (\(Int64(fileSize).formatted(.byteCount(style: .file))))",
                           isOn: $removeFile)
                }
                HStack {
                    Button("Don't Install It", role: .destructive) { installer.answerPendingQuestion(.cancelUpdate) }
                        .help("Removes update.tar from the card and forgets about it")
                    Spacer()
                    Button("Not Yet") { installer.answerPendingQuestion(.notYet) }
                        .keyboardShortcut(.cancelAction)
                    Button("Yes, It's Updated") {
                        installer.answerPendingQuestion(.finished(removeFile: fileSize != nil && removeFile))
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 480)
        } else {
            // The card went away while asking.
            VStack(spacing: 12) {
                Text("The Q2 was disconnected.")
                Button("OK") { installer.isAskingAboutPending = false }.keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
    }
}
