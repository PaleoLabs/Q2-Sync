//
//  DeviceMonitor.swift
//  Q2-Sync › App
//
//  PURPOSE
//  Watches for disks being connected and disconnected, recognises the
//  user's Q2 card by its volume UUID, asks about new cards, and ejects.
//
//  HOW IT FITS
//      macOS (NSWorkspace mount/unmount notifications)
//            │
//            ▼
//      DeviceMonitor ──uses──▶ VolumeInfo / VolumeEligibility / DeviceStore (Core)
//            │
//            ▼
//      Sidebar "Devices" section, DeviceView, NewDeviceSheet
//
//  SAFETY
//  • Only volumes passing `VolumeEligibility` are ever considered.
//  • A card is "the Q2" only when its UUID matches one the user confirmed
//    AND the saved bookmark resolves to a volume with that same UUID. A
//    different drive with the same name is never mistaken for it.
//  • Write access comes only from a security-scoped bookmark the user
//    granted for that card in an Open panel.
//  • Before access is granted, we only read volume metadata (name, size,
//    UUID). We never list or open files on an unconfirmed drive.
//

import AppKit
import Observation
import OSLog

/// The user's Q2 card, connected and ready.
struct ConnectedDevice: Equatable {
    /// The saved device record.
    var device: KnownDevice
    /// Live facts about the mounted volume.
    var volume: VolumeInfo
    /// The card root URL with sandbox access (from the bookmark), or `nil`
    /// if access couldn't be restored.
    var accessURL: URL?
    /// Why `accessURL` is `nil`, for the UI.
    var accessProblem: String?
    /// How the card is connected: through the Q2 or a card reader.
    var connection: CardConnection = .unknown
    /// When this card was mounted (kept across an eject that failed), so
    /// "since the last connection" questions can be answered.
    var connectedAt: Date = .now
}

/// Tracks mounted volumes and the user's Q2.
@MainActor
@Observable
final class DeviceMonitor {

    // MARK: State the UI reads

    /// The confirmed Q2 card, if one is connected.
    private(set) var connected: ConnectedDevice?

    /// A newly seen eligible drive waiting for the user to say whether it's
    /// their Q2. Drives the "Is this your Q2?" sheet.
    var pendingVolume: VolumeInfo?

    /// Eligible drives the user postponed ("Later") this session, and new
    /// drives that don't look like a Q2 (a card reader, a USB stick), which
    /// don't pop up the setup sheet. Shown in the sidebar with "Set Up…".
    private(set) var postponedVolumes: [VolumeInfo] = []

    /// Other mounted cards already set up as a Q2, besides `connected`.
    /// One card is shown at a time; these are listed in the sidebar so you
    /// can switch to one.
    private(set) var otherKnownVolumes: [VolumeInfo] = []

    /// The card to connect to when several known cards are mounted: the
    /// one just set up, or the one the user switched to.
    private var preferredUUID: String?

    /// The last error to show in an alert, if any.
    var errorMessage: String?

    /// `true` while an eject is in progress.
    private(set) var isEjecting = false

    /// Called whenever the user's Q2 connects and is ready (used by
    /// auto-sync).
    var onDeviceConnected: ((ConnectedDevice) -> Void)?

    /// Called when a new drive starts waiting for the "Is this your Q2?"
    /// sheet, so the user can be told even with the window closed.
    var onNewDriveNeedsSetUp: ((VolumeInfo) -> Void)?

    /// Q2 Sync's record of the connected card (for the capacity bar), or
    /// `nil` if it couldn't be read.
    private(set) var cardManifest: SyncManifest?

    /// The Mac-side record of what was on each Q2's card when last read,
    /// by volume UUID. Lets the library browser mark "On Q2" while the Q2
    /// is unplugged. Saved whenever the card's manifest is read.
    private(set) var cardContents: [String: CardContentsRecord] = [:]

    // MARK: Private

    /// Saved devices and ignored drives.
    private let store: DeviceStore

    /// Where `cardContents` is saved (Application Support).
    private let contentsStore: CardContentsStore

    /// UUIDs postponed this session (not saved: asked again next launch).
    private var postponedUUIDs: Set<String> = []

    /// How each mounted drive is connected, by volume UUID. Read once per
    /// mount and forgotten when the drive goes away.
    private var connections: [String: CardConnection] = [:]

    /// How each mounted drive is laid out (scheme and sizes), by volume
    /// UUID (read with the connection, for `CardFormatAdvice`).
    private var cardLayouts: [String: CardPartitions] = [:]

    /// Our notification observers, kept so they stay registered.
    private var observers: [NSObjectProtocol] = []

    private static let logger = Logger(subsystem: "io.github.q2sync.Q2Sync", category: "device")

    /// Creates the monitor.
    /// - Parameters:
    ///   - store: Where devices are remembered.
    ///   - contentsStore: Where each Q2's last known contents are kept.
    init(store: DeviceStore = DeviceStore(), contentsStore: CardContentsStore = CardContentsStore()) {
        self.store = store
        self.contentsStore = contentsStore
        for device in store.knownDevices {
            if let record = contentsStore.load(volumeUUID: device.volumeUUID) {
                cardContents[device.volumeUUID] = record
            }
        }
    }

    /// `true` once any Q2 has been set up on this Mac.
    var hasKnownDevices: Bool { !store.knownDevices.isEmpty }

    /// The Q2 the library browser compares against: the connected one, or
    /// else the one read most recently. `nil` before any Q2 has been read.
    var referenceContents: (device: KnownDevice, record: CardContentsRecord)? {
        if let connected, let record = cardContents[connected.device.volumeUUID] {
            return (connected.device, record)
        }
        return store.knownDevices
            .compactMap { device in cardContents[device.volumeUUID].map { (device, $0) } }
            .max { $0.1.checkedAt < $1.1.checkedAt }
    }

    // MARK: - Watching

    /// Starts watching for mounts and checks what's already connected.
    ///
    /// - Side effects: Registers NSWorkspace notification observers.
    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification,
        ]
        for name in names {
            // `queue: .main` delivers on the main thread, and
            // `MainActor.assumeIsolated` tells the compiler we know that,
            // so we can call our main-actor method synchronously.
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append(observer)
        }
        // Save a selection change still waiting when the app quits.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushPendingSave() }
        })
        refresh()
    }

    /// Re-reads every mounted volume and updates `connected`,
    /// `pendingVolume` and `postponedVolumes`.
    ///
    /// Re-scanning everything on each notification is simpler and more
    /// robust than tracking individual mount events.
    func refresh() {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        var eligible = urls.compactMap(VolumeInfo.read).filter(VolumeEligibility.isEligible)
        // A card busy with a sync can fail a metadata read (or briefly drop
        // out of the mounted list) when another drive is ejected. Before,
        // that disconnected it mid-sync and the sidebar went empty. Only a
        // card whose mount point is really gone counts as unplugged; until
        // then it keeps its last known facts.
        if let current = connected, !eligible.contains(where: { $0.uuid == current.device.volumeUUID }),
           Self.isStillMounted(current.volume.url) {
            Self.logger.notice("Connected card didn't answer a volume read; still mounted, keeping it")
            eligible.append(VolumeInfo.read(at: current.volume.url)
                .flatMap { $0.uuid == current.device.volumeUUID ? $0 : nil } ?? current.volume)
        }
        updateConnections(for: eligible)

        // 1. Is the connected Q2 still mounted?
        if let current = connected, !eligible.contains(where: { $0.uuid == current.device.volumeUUID }) {
            disconnect()
        }

        // 2. Connect to a known device if one is mounted.
        if connected == nil, let match = firstKnownDevice(in: eligible) {
            connect(device: match.device, volume: match.volume)
        } else if let current = connected,
                  let volume = eligible.first(where: { $0.uuid == current.device.volumeUUID }) {
            if volume.name != current.volume.name || volume.url.path != current.volume.url.path {
                // Renamed while connected. The mount point moves with the
                // name, so the old access URL no longer leads to the card:
                // resolve the bookmark again (which also takes the new name).
                flushPendingSave()
                current.accessURL?.stopAccessingSecurityScopedResource()
                connect(device: current.device, volume: volume, connectedAt: current.connectedAt,
                        isRestoring: true)
            } else {
                connected?.volume = volume // Update free space etc.
            }
        }
        otherKnownVolumes = eligible.filter { volume in
            guard let uuid = volume.uuid else { return false }
            return uuid != connected?.device.volumeUUID && store.device(withUUID: uuid) != nil
        }

        // 3. Unknown drives: ask once, unless ignored or postponed.
        let unknown = eligible.filter { volume in
            guard let uuid = volume.uuid else { return false }
            return store.device(withUUID: uuid) == nil && !store.isIgnored(uuid: uuid)
        }
        // Only drives that look like a Q2 (or can't be told) pop up the
        // sheet; card readers and USB sticks wait quietly in the sidebar.
        let asksByItself: (VolumeInfo) -> Bool = { [self] volume in
            !postponedUUIDs.contains(volume.uuid ?? "") && connection(for: volume).promptsForSetUp
        }
        // Drives are matched by ID, not `==`: a fresh read differs in free
        // space (a newly formatted card changes while macOS writes its
        // Spotlight files), which made Set Up… drop the drive it had just
        // picked, so the sheet never opened.
        postponedVolumes = unknown.filter { !asksByItself($0) && $0.id != pendingVolume?.id }
        if let pending = pendingVolume {
            if let fresh = unknown.first(where: { $0.id == pending.id }) {
                pendingVolume = fresh // Same drive; keep its facts current.
            } else {
                pendingVolume = nil // It was unplugged while we were asking.
            }
        }
        if pendingVolume == nil, connected == nil {
            pendingVolume = unknown.first(where: asksByItself)
            postponedVolumes.removeAll { $0.id == pendingVolume?.id }
            if let pendingVolume { onNewDriveNeedsSetUp?(pendingVolume) }
        }
    }

    /// `true` if a file system is still mounted at exactly this path.
    ///
    /// Asks the kernel (`statfs`) rather than trusting the volume list:
    /// once a drive is unmounted its mount point is either gone or belongs
    /// to the startup disk, so the mount path no longer matches.
    nonisolated static func isStillMounted(_ url: URL) -> Bool {
        var info = statfs()
        guard statfs(url.path, &info) == 0 else { return false }
        let mountedOn = withUnsafePointer(to: &info.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return URL(fileURLWithPath: mountedOn).standardizedFileURL.path == url.standardizedFileURL.path
    }

    /// How a mounted drive is connected (through the Q2 or otherwise).
    func connection(for volume: VolumeInfo) -> CardConnection {
        connections[volume.uuid ?? ""] ?? .unknown
    }

    /// Advice if the card isn't one volume filling a Master Boot Record
    /// card, or `nil` if it is or its layout couldn't be read.
    func formatAdvice(for volume: VolumeInfo) -> CardFormatAdvice? {
        CardFormatAdvice.check(layout: cardLayouts[volume.uuid ?? ""])
    }

    /// How a mounted drive is partitioned, if known.
    func partitionScheme(for volume: VolumeInfo) -> PartitionScheme? {
        cardLayouts[volume.uuid ?? ""]?.scheme
    }

    /// Reads the connection (and card layout) of newly mounted drives
    /// and forgets drives that went away.
    private func updateConnections(for volumes: [VolumeInfo]) {
        let mounted = Set(volumes.compactMap(\.uuid))
        connections = connections.filter { mounted.contains($0.key) }
        cardLayouts = cardLayouts.filter { mounted.contains($0.key) }
        for volume in volumes {
            guard let uuid = volume.uuid, connections[uuid] == nil else { continue }
            let connection = CardConnection.classify(DriveIdentityReader.identity(forVolumeAt: volume.url))
            connections[uuid] = connection
            Self.logger.notice("Drive connection: \(connection.rawValue, privacy: .public)")
            // Through the Q2 (USB Storage), its Linux storage gadget shows
            // the Mac only the card's volume, as a whole disk: the card's
            // partition table can't be seen, so it isn't judged. A card
            // reader shows the real scheme.
            if connection != .q2, let layout = DriveIdentityReader.cardLayout(forVolumeAt: volume.url, volumeName: volume.name) {
                cardLayouts[uuid] = layout
                Self.logger.notice("Partition scheme: \(layout.scheme.displayName, privacy: .public); volume \(layout.volumeBytes ?? -1) of \(layout.cardBytes ?? -1) bytes")
            }
        }
    }

    /// Finds the first mounted volume whose UUID belongs to a confirmed Q2.
    ///
    /// - Parameter volumes: Eligible mounted volumes.
    /// - Returns: The volume and its saved record, or `nil`.
    private func firstKnownDevice(in volumes: [VolumeInfo]) -> (volume: VolumeInfo, device: KnownDevice)? {
        // The preferred card first (just set up, or switched to).
        let ordered = volumes.filter { $0.uuid != nil && $0.uuid == preferredUUID }
            + volumes.filter { $0.uuid == nil || $0.uuid != preferredUUID }
        for volume in ordered {
            if let uuid = volume.uuid, let device = store.device(withUUID: uuid) {
                return (volume, device)
            }
        }
        return nil
    }

    // MARK: - Connecting

    /// Restores sandbox access to a known card from its bookmark.
    ///
    /// - Parameters:
    ///   - device: The saved record.
    ///   - volume: The mounted volume with the matching UUID.
    ///   - connectedAt: When the card was mounted; pass the old value when
    ///     reconnecting after a failed eject or a rename.
    ///   - isRestoring: `true` after a failed eject or a rename: the card
    ///     never left, so `onDeviceConnected` isn't called.
    /// - Side effects: Starts security-scoped access (balanced in
    ///   `disconnect()`); may save a new card name or a refreshed bookmark
    ///   in the store.
    private func connect(device: KnownDevice, volume: VolumeInfo, connectedAt: Date = .now,
                         isRestoring: Bool = false) {
        var device = device
        if device.followVolumeName(volume.name) {
            try? store.upsert(device)
        }
        let connection = connection(for: volume)
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: device.bookmarkData,
                              options: [.withSecurityScope],
                              bookmarkDataIsStale: &isStale)
            guard url.startAccessingSecurityScopedResource() else {
                throw CocoaError(.fileReadNoPermission)
            }
            // Double-check the bookmark leads to the SAME card.
            guard VolumeInfo.read(at: url)?.uuid == device.volumeUUID else {
                url.stopAccessingSecurityScopedResource()
                connected = ConnectedDevice(device: device, volume: volume, accessURL: nil,
                                            accessProblem: "The saved access points to a different drive. Grant access again.",
                                            connection: connection, connectedAt: connectedAt)
                return
            }
            if isStale, let fresh = try? url.bookmarkData(options: [.withSecurityScope]) {
                device.bookmarkData = fresh
                try? store.upsert(device)
            }
            connected = ConnectedDevice(device: device, volume: volume, accessURL: url, accessProblem: nil,
                                        connection: connection, connectedAt: connectedAt)
            reloadManifest()
            Self.logger.notice("Connected to known Q2 card")
            if !isRestoring, let connected { onDeviceConnected?(connected) }
        } catch {
            connected = ConnectedDevice(device: device, volume: volume, accessURL: nil,
                                        accessProblem: "Q2 Sync no longer has permission to use this card. Grant access again.",
                                        connection: connection, connectedAt: connectedAt)
        }
    }

    /// Clears the connected device and releases sandbox access.
    private func disconnect() {
        flushPendingSave()
        // Unapplied edits go with the card (unplugged, or switched to
        // another Q2), as in Finder.
        discardUnappliedChanges()
        connected?.accessURL?.stopAccessingSecurityScopedResource()
        connected = nil
        cardManifest = nil
        manifestReadGeneration += 1 // Drop a read still in flight.
    }

    /// Re-reads the card's manifest (read-only), e.g. after a sync.
    ///
    /// Read and decoded in the background: the manifest is several MB on a
    /// big card, and reading it on the main thread over the Q2's USB froze
    /// the window. Until it arrives, the previous value stays (or `nil`
    /// on a new connection: the capacity bar shows the card as unknown).
    /// A read that finishes after the card changed is dropped.
    func reloadManifest() {
        guard let current = connected, let root = current.accessURL else {
            manifestReadGeneration += 1
            cardManifest = nil
            return
        }
        manifestReadGeneration += 1
        let generation = manifestReadGeneration
        let uuid = current.device.volumeUUID
        let profile = current.device.profile
        let contentsStore = contentsStore
        Task { [weak self] in
            let read = await Task.detached(priority: .userInitiated) { () -> (SyncManifest, CardContentsRecord)? in
                guard let manifest = try? SyncManifest.load(cardRoot: root, profile: profile) else { return nil }
                // Keep the Mac-side note in step. A manifest that couldn't be
                // read leaves the old note alone rather than claiming the
                // card is empty.
                let record = CardContentsRecord(volumeUUID: uuid, manifest: manifest)
                contentsStore.save(record)
                return (manifest, record)
            }.value
            guard let self, generation == self.manifestReadGeneration,
                  self.connected?.device.volumeUUID == uuid else { return }
            self.cardManifest = read?.0
            if let record = read?.1 { self.cardContents[record.volumeUUID] = record }
        }
    }

    /// Counts manifest reads, so only the latest one is used.
    @ObservationIgnored private var manifestReadGeneration = 0

    /// Updates free space and the manifest after the card's contents changed.
    func reloadCardInfo() {
        refresh()
        reloadManifest()
    }

    // MARK: - First-connection flow

    /// The user confirmed a drive is their Q2. Asks macOS for write access
    /// to it via an Open panel, then remembers it.
    ///
    /// - Parameters:
    ///   - volume: The drive the user confirmed.
    ///   - firmware: The firmware they said it runs.
    /// - Side effects: Shows an Open panel; saves the device; connects.
    func confirm(_ volume: VolumeInfo, firmware: FirmwareKind) {
        guard let uuid = volume.uuid else { return }

        guard let grantedURL = CardAccessPanel.requestAccess(to: volume) else {
            return // User cancelled; the sheet stays so they can try again.
        }
        defer { grantedURL.stopAccessingSecurityScopedResource() }

        // The user must have picked the card's root, not another folder.
        guard grantedURL.standardizedFileURL.path == volume.url.standardizedFileURL.path,
              VolumeInfo.read(at: grantedURL)?.uuid == uuid else {
            errorMessage = "Please select the card itself (“\(volume.name)”), not a folder on it or another drive."
            return
        }

        do {
            let bookmark = try grantedURL.bookmarkData(options: [.withSecurityScope])
            let device = KnownDevice(volumeUUID: uuid, name: volume.name, firmware: firmware,
                                     bookmarkData: bookmark, addedDate: .now, hasCompletedFirstSync: false)
            try store.upsert(device)
            pendingVolume = nil
            postponedUUIDs.remove(uuid)
            // Show the card just set up, even if another Q2 card is
            // connected too (before, the first one found won, and the new
            // card seemed to vanish from the sidebar).
            preferredUUID = uuid
            disconnect()
            refresh()
        } catch {
            errorMessage = "Couldn't remember this card: \(error.localizedDescription)"
        }
    }

    /// Shows another mounted Q2 card instead of the connected one.
    ///
    /// - Parameter volume: One of `otherKnownVolumes`.
    /// - Side effects: Releases the current card's access and connects to
    ///   the other one (which may start an automatic sync, as plugging it
    ///   in would). Callers must not switch while a card is busy.
    func switchTo(_ volume: VolumeInfo) {
        guard let uuid = volume.uuid, store.device(withUUID: uuid) != nil else { return }
        preferredUUID = uuid
        disconnect()
        refresh()
    }

    /// Re-grants access for the connected card (e.g. after a stale bookmark).
    func regrantAccess() {
        guard let current = connected else { return }
        // Stay connected while the Open panel is up: `confirm` reconnects
        // with the new access only if it's granted, so cancelling (or
        // picking the wrong folder) leaves the Q2 in the sidebar.
        confirm(current.volume, firmware: current.device.firmware)
    }

    /// The user said the drive is not their Q2. Remembered permanently.
    func markNotQ2(_ volume: VolumeInfo) {
        guard let uuid = volume.uuid else { return }
        try? store.ignore(uuid: uuid)
        pendingVolume = nil
        refresh()
    }

    /// The user wants to decide later. Asked again next launch.
    func postpone(_ volume: VolumeInfo) {
        guard let uuid = volume.uuid else { return }
        postponedUUIDs.insert(uuid)
        pendingVolume = nil
        refresh()
    }

    /// Forgets every "Not My Q2" answer, so those drives are offered again.
    func clearIgnoredDrives() {
        try? store.clearIgnored()
        refresh()
    }

    /// Re-opens the setup sheet for a postponed drive.
    func setUp(_ volume: VolumeInfo) {
        postponedUUIDs.remove(volume.uuid ?? "")
        pendingVolume = volume
        refresh()
    }

    // MARK: - Managing the known device

    /// Changes which firmware the connected Q2 runs.
    func setFirmware(_ firmware: FirmwareKind) {
        guard var device = connected?.device else { return }
        device.firmware = firmware
        do {
            try store.upsert(device)
            connected?.device = device
        } catch {
            errorMessage = "Couldn't save the firmware choice: \(error.localizedDescription)"
        }
    }

    /// `true` if the connected card holds songs Q2 Sync put there. Then an
    /// empty selection is a real choice (remove them all); otherwise
    /// there's nothing to sync yet.
    var cardHasQ2SyncSongs: Bool {
        !(cardManifest?.entries.isEmpty ?? true)
    }

    // MARK: - Unapplied changes (Revert / Apply)

    /// Edits made on the Q2's page and not applied yet, like Finder's
    /// iPod page. Kept in memory only: quitting throws them away.
    private(set) var unappliedChanges = UnappliedChanges()

    /// What the Q2's page shows for the connected Q2: its unapplied edits,
    /// or the saved settings.
    var shownSyncSettings: DeviceSyncSettings? {
        connected.map { unappliedChanges.settings(for: $0.device) }
    }

    /// `true` if the connected Q2 has edits waiting for Revert or Apply.
    var hasUnappliedChanges: Bool {
        connected.map { unappliedChanges.hasChanges(for: $0.device) } ?? false
    }

    /// Edits the connected Q2's settings without saving them (until Apply).
    ///
    /// - Parameter change: Edits a copy of the shown settings in place.
    func editSyncSettings(_ change: (inout DeviceSyncSettings) -> Void) {
        guard let device = connected?.device else { return }
        unappliedChanges.edit(device, change)
    }

    /// Revert: puts the connected Q2's saved settings back on its page.
    func revertUnappliedChanges() {
        guard let uuid = connected?.device.volumeUUID else { return }
        unappliedChanges.discard(volumeUUID: uuid)
    }

    /// Apply: saves the connected Q2's edits now.
    ///
    /// - Returns: `true` if there were edits and they were saved.
    /// - Side effects: Writes `devices.json` in the app's container.
    @discardableResult
    func applyUnappliedChanges() -> Bool {
        guard let device = connected?.device,
              let changes = unappliedChanges.changes(for: device) else { return false }
        saveSyncSettings(changes)
        unappliedChanges.discard(volumeUUID: device.volumeUUID)
        return true
    }

    /// Throws away every unapplied edit: called on leaving the Q2's page
    /// and when the Q2 disconnects, as Finder does.
    func discardUnappliedChanges() {
        unappliedChanges.discardAll()
    }

    /// Saves sync settings for the connected Q2 at once.
    ///
    /// - Parameter settings: Every kind of content's settings. A new kind
    ///   (audiobooks…) is saved here too.
    private func saveSyncSettings(_ settings: DeviceSyncSettings) {
        setSelection(settings.music)
        flushPendingSave()
        if connected?.device.effectiveAudiobooks != settings.audiobooks {
            updateConnectedDevice { $0.audiobooks = settings.audiobooks }
        }
    }

    /// Saves a new sync selection for the connected Q2.
    ///
    /// - Parameter selection: The updated selection.
    /// - Side effects: Writes `devices.json` in the app's container.
    func setSelection(_ selection: SyncSelection) {
        guard var device = connected?.device, device.selection != selection else { return }
        device.selection = selection
        connected?.device = device
        // Saved to disk half a second after the last click, not on every
        // click (each save rewrites every Q2's settings). `flushPendingSave`
        // saves at once before a sync, on disconnect and when quitting.
        pendingSelection = (device.volumeUUID, selection)
        pendingSelectionSave?.cancel()
        pendingSelectionSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.flushPendingSave()
        }
    }

    /// A selection change not saved to disk yet, and its timer.
    @ObservationIgnored private var pendingSelection: (uuid: String, selection: SyncSelection)?
    @ObservationIgnored private var pendingSelectionSave: Task<Void, Never>?

    /// Saves a pending selection change now, if there is one. Merged into
    /// the stored record, so other settings saved meanwhile aren't undone.
    func flushPendingSave() {
        pendingSelectionSave?.cancel()
        pendingSelectionSave = nil
        guard let pending = pendingSelection else { return }
        pendingSelection = nil
        guard var device = store.device(withUUID: pending.uuid) else { return }
        device.selection = pending.selection
        do {
            try store.upsert(device)
        } catch {
            errorMessage = "Couldn't save your selection: \(error.localizedDescription)"
        }
    }

    /// Saves the firmware version the user typed in (blank clears it).
    func setInstalledFirmwareVersion(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        updateConnectedDevice { $0.installedFirmwareVersion = trimmed.isEmpty ? nil : trimmed }
    }

    /// Hides a firmware release until a newer one comes out.
    func dismissFirmwareRelease(_ tag: String) {
        updateConnectedDevice { $0.dismissedFirmwareRelease = tag }
    }

    /// Records that firmware was put on the card, waiting for the Q2 to
    /// install it (or clears that record with `nil`).
    func setPendingFirmwareInstall(_ pending: PendingFirmwareInstall?) {
        updateConnectedDevice { $0.pendingFirmwareInstall = pending }
    }

    /// The user confirmed the Q2 installed the pending firmware: switch
    /// the device to it and record its version.
    func completePendingFirmwareInstall() {
        updateConnectedDevice { device in
            guard let image = device.pendingFirmwareInstall?.image else { return }
            device.firmware = image.kind
            // The version field is Q2 Pod's "CFW. Version", used for its
            // update checks; stock has none.
            device.installedFirmwareVersion = image.kind == .q2Pod ? image.version : nil
            device.dismissedFirmwareRelease = nil
            device.pendingFirmwareInstall = nil
        }
    }

    /// Turns album covers on or off for the connected Q2.
    func setAlbumCovers(_ on: Bool) {
        updateConnectedDevice { $0.albumCovers = on }
    }

    /// Turns "only changed playlists up for import" on or off.
    func setImportOnlyChangedPlaylists(_ on: Bool) {
        updateConnectedDevice { $0.importOnlyChangedPlaylists = on }
    }

    /// Asks for (or clears) a full playlist re-import at the next sync.
    func setReimportAllPlaylists(_ on: Bool) {
        updateConnectedDevice { $0.reimportAllPlaylists = on ? true : nil }
    }

    /// Changes what happens when this Q2 connects.
    func setAutoSync(_ mode: AutoSyncMode) {
        updateConnectedDevice { $0.autoSync = mode }
    }

    /// Records that a real sync finished successfully.
    func markSyncCompleted() {
        updateConnectedDevice { $0.hasCompletedFirstSync = true }
    }

    /// Edits and saves the connected device's record.
    private func updateConnectedDevice(_ change: (inout KnownDevice) -> Void) {
        guard var device = connected?.device else { return }
        change(&device)
        do {
            try store.upsert(device)
            connected?.device = device
        } catch {
            errorMessage = "Couldn't save the device's settings: \(error.localizedDescription)"
        }
    }

    /// Forgets the connected Q2 (its access and settings). Nothing on the
    /// card is changed. The drive will be offered as new again.
    func forgetConnectedDevice() {
        guard let uuid = connected?.device.volumeUUID else { return }
        disconnect()
        try? store.forget(uuid: uuid)
        contentsStore.remove(volumeUUID: uuid)
        cardContents[uuid] = nil
        refresh()
    }

    // MARK: - Ejecting

    /// Ejects the connected Q2 card.
    ///
    /// On failure the card stays mounted and the error is shown, as the
    /// app's requirements specify.
    ///
    /// - Returns: `true` if ejected.
    /// - Side effects: Releases sandbox access, then unmounts and ejects.
    @discardableResult
    func eject() async -> Bool {
        guard let current = connected else { return false }
        isEjecting = true
        defer { isEjecting = false }

        // Release our access first; an open handle can block unmounting.
        current.accessURL?.stopAccessingSecurityScopedResource()
        do {
            try await FileManager.default.unmountVolume(at: current.volume.url,
                                                        options: [.allPartitionsAndEjectDisk])
            connected = nil
            refresh()
            return true
        } catch {
            // Still mounted: restore access so the user can carry on. Not a
            // new connection, so nothing that runs on connecting (auto-sync,
            // its notification, the firmware question) should run again.
            connect(device: current.device, volume: current.volume, connectedAt: current.connectedAt,
                    isRestoring: true)
            errorMessage = "The card couldn't be ejected. Close any windows or apps using it and try again. (\(error.localizedDescription))"
            return false
        }
    }
}

/// Shows the Open panel that grants the sandboxed app access to the card.
enum CardAccessPanel {

    /// Asks the user to select the card's root folder.
    ///
    /// - Parameter volume: The card to pre-select.
    /// - Returns: The chosen URL with security-scoped access already
    ///   started (the caller must call `stopAccessingSecurityScopedResource`),
    ///   or `nil` if cancelled.
    @MainActor
    static func requestAccess(to volume: VolumeInfo) -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Select your Q2's card “\(volume.name)” and click Grant Access. Q2 Sync will only be able to change files on this card."
        panel.prompt = "Grant Access"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = volume.url
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }
}
