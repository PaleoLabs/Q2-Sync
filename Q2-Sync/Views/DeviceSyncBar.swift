//
//  DeviceSyncBar.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The bar at the bottom of the Q2's page, below every tab, like Finder's
//  iPod page: the capacity bar, and the buttons that act on the sync.
//
//      no unapplied edits   →  Sync
//      edits not applied    →  Revert  Apply
//      a sync under way     →  Stop
//
//  Revert puts the saved choices back. Apply saves the edits, then starts
//  a sync (the review sheet opens, as for Sync). Stop cancels the sync;
//  applied choices stay saved.
//
//  HOW IT FITS
//  Shown by `DeviceView`. Edits live in `DeviceMonitor.unappliedChanges`;
//  syncs start through `AutoSyncController.startSync`, as from the menus.
//

import SwiftUI

/// Capacity bar plus Sync / Revert / Apply / Stop.
struct DeviceSyncBar: View {

    let connected: ConnectedDevice
    let devices: DeviceMonitor

    /// What the card holds and what the shown choices would put on it.
    let estimate: CapacityEstimate

    /// Runs syncs (from the environment, set up in `Q2SyncApp`).
    @Environment(SyncCoordinator.self) private var sync

    /// Starts syncs the same way the menu bar does.
    @Environment(AutoSyncController.self) private var autoSync

    var body: some View {
        // Buttons line up with the bar itself, like Finder.
        HStack(alignment: .capacityBarCenter, spacing: 12) {
            CapacityBarView(estimate: estimate)
            buttons
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Buttons

    @ViewBuilder
    private var buttons: some View {
        if isSyncing {
            Button("Stop") { sync.cancel() }
                .help("Stop the sync. Your choices stay saved.")
        } else if devices.hasUnappliedChanges {
            Button("Revert") { devices.revertUnappliedChanges() }
                .help("Undo your changes")
            Button("Apply") {
                devices.applyUnappliedChanges()
                if canSync { startSync() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(sync.phase != .idle)
            .help(canSync ? "Save your changes, then sync them to the Q2" : "Save your changes")
        } else {
            Button {
                startSync()
            } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSync)
            .help(nothingChosen ? "Choose some music first" : "Review the changes, then copy them to the Q2")
        }
    }

    // MARK: - State

    /// `true` from Sync (or Apply) until the copy ends: planning, the
    /// review sheet, and copying. Not while the result is showing.
    private var isSyncing: Bool {
        switch sync.phase {
        case .planning, .preview, .running: true
        case .idle, .finished, .failed: false
        }
    }

    /// `true` when nothing is chosen and the card holds no Q2 Sync songs
    /// to remove, so a sync would do nothing.
    private var nothingChosen: Bool {
        let shown = devices.shownSyncSettings ?? connected.device.syncSettings
        return shown.music.isEmpty && !devices.cardHasQ2SyncSongs
    }

    /// `true` if a sync could start now with the shown choices.
    private var canSync: Bool {
        sync.phase == .idle && connected.accessURL != nil && !nothingChosen
    }

    /// Starts a sync of the saved choices (the review sheet opens).
    private func startSync() {
        Task { await autoSync.startSync(automatic: false) }
    }
}
