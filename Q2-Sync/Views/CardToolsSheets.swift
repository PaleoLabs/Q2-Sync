//
//  CardToolsSheets.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  • `VerifyCardSheet`: check every song on the card against the Mac,
//    then re-copy damaged or missing ones.
//  • `PodDataSection` + `RestorePodDataSheet`: back up Q2 Pod's data on
//    the card (ratings, EQ presets…) to the Mac, and put it back.
//
//  HOW IT FITS
//  The sheets are presented by `RootView`; the section sits in
//  `DeviceSettingsView`. State lives in `CardVerifyModel` / `PodDataModel`.
//

import AppKit
import SwiftUI

// MARK: - Verify Card

/// Verifies the card's songs.
struct VerifyCardSheet: View {

    let model: CardVerifyModel
    let devices: DeviceMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield").font(.system(size: 32)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Verify Card").font(.title2.bold())
                    if let name = devices.connected?.device.name {
                        Text("“\(name)”").foregroundStyle(.secondary)
                    }
                }
            }
            switch model.phase {
            case .ready: ready
            case .checking: working(title: "Checking songs…", cancel: "Stop")
            case .checked: checked
            case .repairing: working(title: "Copying songs again…", cancel: "Stop")
            case .repaired: repaired
            case .failed(let message): failed(message)
            }
        }
        .padding(24)
        .frame(width: 520)
        .interactiveDismissDisabled(model.isBusy)
    }

    @ViewBuilder
    private var ready: some View {
        Text("Q2 Sync reads every song it put on the card and compares it, byte for byte, with the song on your Mac. microSD cards can damage files without any warning; this finds them so they can be copied again.")
            .fixedSize(horizontal: false, vertical: true)
        Label("Nothing is changed while checking. Reading the whole card can take a while over USB; a card reader is faster. You can stop at any time.",
              systemImage: "info.circle")
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        HStack {
            Spacer()
            Button("Cancel") { model.close() }.keyboardShortcut(.cancelAction)
            Button("Start Checking") { model.startCheck() }.keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private func working(title: String, cancel: String) -> some View {
        let progress = model.progress
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            ProgressView(value: progress.fraction)
            Text(model.secondsRemaining.map(TimeRemainingEstimator.describe) ?? "Estimating time remaining…")
                .font(.callout).foregroundStyle(.secondary)
            Text(progress.current.isEmpty ? " " : progress.current).lineLimit(1).truncationMode(.middle)
            Text("\(progress.songsDone.formatted()) of \(progress.totalSongs.formatted()) songs · "
                 + "\(Int64(progress.bytesDone).formatted(.byteCount(style: .file))) of "
                 + "\(Int64(progress.totalBytes).formatted(.byteCount(style: .file)))")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
        }
        HStack {
            Text("Keep the card connected.").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button(cancel) { model.cancel() }.keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private var checked: some View {
        if let result = model.result {
            if result.problems.isEmpty {
                Label(result.wasCancelled ? "Stopped. \(result.verified.formatted()) songs checked so far are fine."
                                          : "All \(result.verified.formatted()) songs checked are fine.",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.headline)
            } else {
                Label("\(result.problems.count) songs need copying again.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.headline)
                List(result.problems) { problem in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(problem.title).lineLimit(1)
                        Text("\(problem.explanation) · \(problem.path)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .frame(height: 180)
            }
            skippedNote(result)
            HStack {
                Spacer()
                if result.problems.isEmpty {
                    Button("Done") { model.close() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Close") { model.close() }.keyboardShortcut(.cancelAction)
                    Button("Copy \(result.problems.count) Songs Again") { model.repair() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    @ViewBuilder
    private func skippedNote(_ result: VerifyResult) -> some View {
        let notes = [
            result.skippedChanged > 0 ? "\(result.skippedChanged.formatted()) changed on your Mac since copying (your next sync updates them)" : nil,
            result.skippedNoMacFile > 0 ? "\(result.skippedNoMacFile.formatted()) couldn't be compared because the song isn't on your Mac" : nil,
        ].compactMap { $0 }
        if !notes.isEmpty {
            Text("Not checked: " + notes.joined(separator: "; ") + ".")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var repaired: some View {
        if let report = model.repairReport {
            if report.succeeded {
                Label("Copied \(report.updated) songs again. They're fine now.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.headline)
            } else {
                Label(report.abortReason ?? (report.wasCancelled ? "Stopped." : "\(report.errors.count) songs couldn't be copied."),
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if report.updated > 0 {
                Text("If the same songs keep coming back damaged, the card may be failing. Consider replacing it.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if let log = report.logURL {
                    Button("Show Log") { NSWorkspace.shared.activateFileViewerSelecting([log]) }
                }
                Spacer()
                Button("Done") { model.close() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private func failed(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        HStack {
            Spacer()
            Button("Close") { model.close() }.keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Q2 Pod data

/// The "Q2 Pod Data" part of a Q2's Settings tab.
struct PodDataSection: View {

    let model: PodDataModel
    let connected: ConnectedDevice
    let isBlocked: Bool

    var body: some View {
        Section {
            if model.filesOnCard.isEmpty {
                Text("No Q2 Pod data on this card yet.").foregroundStyle(.secondary)
            } else {
                let items = PodDataBackup.items.filter { item in
                    model.filesOnCard.contains { PodDataBackup.belongs($0.path, to: item) }
                }
                Text("On this card: " + items.map(\.label).joined(separator: ", ") + ".")
                    .fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("Backup folder") {
                HStack {
                    Text(model.backupFolder.displayName)
                        .foregroundStyle(model.backupFolder.folder == nil ? .orange : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(model.backupFolder.folder?.path ?? "")
                    Button("Change…") { model.chooseBackupFolder() }
                        .disabled(model.isBusy)
                    if model.backupFolder.isCustom {
                        Button("Use Default") { model.useDefaultBackupFolder() }
                            .disabled(model.isBusy)
                            .help("Back up to Downloads › Q2 Sync Backups")
                    }
                }
            }
            if let problem = model.backupFolder.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let latest = model.backupsOfThisCard.first {
                LabeledContent("Last backup", value: latest.created.formatted(date: .abbreviated, time: .shortened))
            }
            if let status = model.status {
                Text(status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Back Up Now") { model.backUp() }
                    .disabled(model.filesOnCard.isEmpty || model.isBusy || isBlocked || connected.accessURL == nil
                              || model.backupFolder.folder == nil)
                Button("Restore…") { chooseBackup() }
                    .disabled(model.isBusy || isBlocked || connected.accessURL == nil)
                Spacer()
                Button("Show Backups") {
                    guard let folder = model.backupFolder.folder else { return }
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(folder)
                }
                .disabled(model.backupFolder.folder == nil)
            }
        } header: {
            Text("Q2 Pod Data")
        } footer: {
            Text("Q2 Pod keeps your song ratings, listens waiting to be scrobbled, scrobbling and radio settings, EQ presets, custom App Store sources and Rockbox settings on the card. Back them up to a folder on your Mac (Downloads › Q2 Sync Backups unless you change it; the same folder for every Q2) in case the card is lost or reformatted. The Q2's own settings are stored inside the Q2, where a Mac can't reach them.")
        }
        .onAppear { model.refresh() }
    }

    /// Picks a backup folder, starting in the backups folder.
    private func chooseBackup() {
        let panel = NSOpenPanel()
        panel.message = "Choose a Q2 Pod data backup to restore to “\(connected.device.name)”."
        panel.prompt = "Choose Backup"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        let folder = model.backupFolder.folder ?? PodDataBackup.backupsFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        panel.directoryURL = model.backupsOfThisCard.first?.folder ?? folder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.chooseBackup(at: url)
    }
}

/// Choose what to put back on the card from a backup.
struct RestorePodDataSheet: View {

    let model: PodDataModel
    let backup: PodDataBackupInfo
    let deviceName: String

    @State private var selected: Set<CardPath> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Restore Q2 Pod Data").font(.title2.bold())
            Text("From the backup of “\(backup.deviceName)” made \(backup.created.formatted(date: .abbreviated, time: .shortened)), to “\(deviceName)”. Ticked items replace what's on the card now.")
                .fixedSize(horizontal: false, vertical: true)
            ForEach(backup.items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(item.label, isOn: Binding(
                        get: { selected.contains(item.path) },
                        set: { if $0 { selected.insert(item.path) } else { selected.remove(item.path) } }))
                    if let warning = item.restoreWarning {
                        Text(warning).font(.caption).foregroundStyle(.orange).padding(.leading, 20)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { model.restoring = nil }.keyboardShortcut(.cancelAction)
                Button("Restore") { model.restore(items: selected) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty || model.isBusy)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear { selected = Set(backup.items.filter(\.restoreByDefault).map(\.path)) }
    }
}
