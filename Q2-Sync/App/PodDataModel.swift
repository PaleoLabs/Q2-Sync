//
//  PodDataModel.swift
//  Q2-Sync › App
//
//  PURPOSE
//  UI state for backing up and restoring Q2 Pod's data on the card
//  (`PodDataBackup`): Back Up Now, the list of backups, and Restore.
//
//  HOW IT FITS
//  Owned by `AutoSyncController`; used by the Settings tab's "Q2 Pod Data"
//  section and `RestorePodDataSheet`. Syncing waits while it works.
//

import Foundation
import Observation

/// Backing up and restoring Q2 Pod's card data.
@MainActor
@Observable
final class PodDataModel {

    /// Data files on the connected card (refreshed on demand).
    private(set) var filesOnCard: [PodDataBackupInfo.File] = []
    /// Backups on this Mac, newest first.
    private(set) var backups: [PodDataBackupInfo] = []
    /// The latest backup made or a message, for the Settings section.
    private(set) var status: String?
    /// `true` while backing up or restoring.
    private(set) var isBusy = false

    /// The backup being restored (drives the restore sheet).
    var restoring: PodDataBackupInfo?

    /// Where backups go (default ~/Downloads/Q2 Sync Backups).
    let backupFolder = BackupFolderSetting()

    private let devices: DeviceMonitor

    init(devices: DeviceMonitor) {
        self.devices = devices
    }

    /// Re-reads what's on the card and which backups exist.
    func refresh() {
        filesOnCard = devices.connected?.accessURL.map { PodDataBackup.filesOnCard(cardRoot: $0) } ?? []
        backups = backupFolder.folder.map { PodDataBackup.existingBackups(in: $0) } ?? []
    }

    /// Lets the user choose another backup folder.
    func chooseBackupFolder() {
        let cards = devices.connected.map { [$0.volume.url] } ?? []
        if let message = backupFolder.choose(refusingCards: cards) { status = message }
        refresh()
    }

    /// Goes back to ~/Downloads/Q2 Sync Backups.
    func useDefaultBackupFolder() {
        backupFolder.useDefault()
        refresh()
    }

    /// Backups of the connected card (matched by its unique ID).
    var backupsOfThisCard: [PodDataBackupInfo] {
        guard let uuid = devices.connected?.device.volumeUUID else { return [] }
        return backups.filter { $0.volumeUUID == uuid }
    }

    /// Copies the card's Q2 Pod data into the backup folder.
    func backUp() {
        guard !isBusy, let connected = devices.connected, let root = connected.accessURL else { return }
        guard let folder = backupFolder.folder else {
            status = backupFolder.problem
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let info = try PodDataBackup.backUp(cardRoot: root, deviceName: connected.device.name,
                                                volumeUUID: connected.device.volumeUUID,
                                                to: folder,
                                                protectedFolders: [PathGuard.defaultHomeMusicFolder, root])
            status = "Backed up \(pluralized(info.files.count, "file")) to \(backupFolder.displayName) › \(info.folder?.lastPathComponent ?? "")."
        } catch {
            status = error.localizedDescription
        }
        refresh()
    }

    /// Opens the restore sheet for a backup folder.
    func chooseBackup(at folder: URL) {
        do {
            restoring = try PodDataBackup.readBackup(at: folder)
        } catch {
            status = error.localizedDescription
        }
    }

    /// Puts the chosen items of `restoring` back on the connected card.
    ///
    /// - Parameter items: The items the user ticked.
    func restore(items: Set<CardPath>) {
        guard !isBusy, let backup = restoring, let folder = backup.folder,
              let connected = devices.connected, let root = connected.accessURL else { return }
        isBusy = true
        defer { isBusy = false }
        let files = backup.files.map(\.path).filter { path in
            PodDataBackup.items.contains { items.contains($0.path) && PodDataBackup.belongs(path, to: $0) }
        }
        do {
            let pathGuard = try PathGuard(cardRoot: root, expectedVolumeUUID: connected.device.volumeUUID,
                                          profile: connected.device.profile)
            let restored = try CardFileSystem(pathGuard: pathGuard).restorePodData(from: folder, files: files)
            status = "Restored \(pluralized(restored, "file")) from the backup of \(backup.created.formatted(date: .abbreviated, time: .shortened)). On the Q2, restart it so Q2 Pod reads them."
            restoring = nil
        } catch {
            status = "Couldn't restore: \(error.localizedDescription)"
        }
        refresh()
    }
}
