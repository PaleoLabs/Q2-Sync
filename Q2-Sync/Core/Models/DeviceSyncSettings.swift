//
//  DeviceSyncSettings.swift
//  Q2-Sync › Core › Models
//
//  PURPOSE
//  What a Q2 is set to sync, across every kind of content, and the edits
//  made on the Q2's page that haven't been applied yet. Like Finder's iPod
//  page: ticking boxes changes nothing until Apply; Revert puts the saved
//  choices back; leaving the device throws the edits away. One Apply
//  covers every content tab at once.
//
//  HOW IT FITS
//  `DeviceMonitor` holds an `UnappliedChanges` and saves on Apply; the
//  device page shows `settings(for:)` and edits through `edit(_:_:)`.
//
//  ADDING A KIND OF CONTENT (audiobooks, podcasts…)
//  Add a property to `DeviceSyncSettings`, read it from `KnownDevice` in
//  `syncSettings`, and save it in `DeviceMonitor.saveSyncSettings`.
//  Revert, Apply and "thrown away when you leave" then cover it as well.
//

import Foundation

/// Everything a Q2 is set to sync. Edits on the Q2's page are a copy of
/// this until Apply saves them.
struct DeviceSyncSettings: Hashable, Sendable {

    /// The Music tab: entire library, or the ticked artists, albums,
    /// genres and playlists.
    var music: SyncSelection
}

extension KnownDevice {

    /// The saved sync settings for this Q2.
    var syncSettings: DeviceSyncSettings {
        DeviceSyncSettings(music: effectiveSelection)
    }
}

/// Edits made on the Q2's page and not applied yet, kept per Q2 (by volume
/// UUID) so several connected Q2s could each have their own.
struct UnappliedChanges: Sendable {

    /// The edited settings, only for Q2s whose edits differ from what's saved.
    private var edits: [String: DeviceSyncSettings] = [:]

    /// What the Q2's page shows: the edits if there are any, else the
    /// saved settings.
    func settings(for device: KnownDevice) -> DeviceSyncSettings {
        edits[device.volumeUUID] ?? device.syncSettings
    }

    /// `true` if the page shows edits that differ from what's saved.
    func hasChanges(for device: KnownDevice) -> Bool {
        guard let edited = edits[device.volumeUUID] else { return false }
        return edited != device.syncSettings
    }

    /// The edits to save, or `nil` if there's nothing to apply.
    func changes(for device: KnownDevice) -> DeviceSyncSettings? {
        hasChanges(for: device) ? edits[device.volumeUUID] : nil
    }

    /// Edits the settings shown for a Q2. Edits that end up the same as
    /// what's saved (ticked, then unticked) count as no change.
    ///
    /// - Parameters:
    ///   - device: The Q2, with its saved settings.
    ///   - change: Edits a copy of the shown settings in place.
    mutating func edit(_ device: KnownDevice, _ change: (inout DeviceSyncSettings) -> Void) {
        var copy = settings(for: device)
        change(&copy)
        edits[device.volumeUUID] = copy == device.syncSettings ? nil : copy
    }

    /// Throws away one Q2's edits (Revert, or after Apply saved them).
    mutating func discard(volumeUUID: String) {
        edits[volumeUUID] = nil
    }

    /// Throws away every Q2's edits (leaving the Q2's page, unplugging).
    mutating func discardAll() {
        edits.removeAll()
    }
}
