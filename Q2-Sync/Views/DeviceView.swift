//
//  DeviceView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The page shown when the Q2 is selected in the sidebar, laid out like
//  Finder's iPod page: a header (icon, name, firmware, capacity, Eject)
//  and two tabs, "Music" (what to sync) and "Settings" (firmware and card).
//
//  HOW IT FITS
//  Shown by `RootView`. Actions go through `DeviceMonitor`; library data
//  comes from `LibraryModel`.
//

import AppKit
import SwiftUI

/// The two tabs on the device page.
enum DeviceTab: String, CaseIterable, Identifiable {
    case music = "Music"
    case settings = "Settings"
    var id: String { rawValue }
}

/// Header plus tabs for the connected Q2.
struct DeviceView: View {

    let connected: ConnectedDevice
    let devices: DeviceMonitor
    let library: LibraryModel

    /// Holds which tab is showing, so the menus can switch it.
    @Environment(AutoSyncController.self) private var autoSync

    /// The last resolved selection and space numbers (see `MusicTabCache`).
    @State private var cache = MusicTabCache()

    var body: some View {
        @Bindable var navigation = autoSync.navigation
        let (resolved, estimate) = resolvedSelection()
        VStack(spacing: 0) {
            DeviceHeaderView(connected: connected, devices: devices, showSettings: { navigation.deviceTab = .settings })
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Picker("Tab", selection: $navigation.deviceTab) {
                ForEach(DeviceTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.bottom, 10)

            Divider()

            Group {
                switch navigation.deviceTab {
                case .music:
                    if let resolved {
                        DeviceMusicView(connected: connected, devices: devices, library: library, resolved: resolved)
                    } else {
                        LibraryNotReadView(library: library)
                    }
                case .settings:
                    DeviceSettingsView(connected: connected, devices: devices)
                }
            }
            // Fill the space so the Sync bar sits at the bottom on every tab.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()
            // Below every tab, like Finder: one Revert/Apply covers them all.
            DeviceSyncBar(connected: connected, devices: devices, estimate: estimate)
        }
        // Fill the whole detail area, pinned to the top, so the header
        // never floats to the middle when the content below is short.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(connected.device.name)
    }

    /// The shown music selection resolved against the library, and the
    /// capacity bar's numbers for it. Redone only when the selection,
    /// library or card changed, not on every redraw (typing in the filter,
    /// switching sections…).
    ///
    /// - Returns: `nil` for the selection before the library has been
    ///   read; the estimate then shows only what the card holds.
    private func resolvedSelection() -> (ResolvedSelection?, CapacityEstimate) {
        guard let snapshot = library.snapshot else { return (nil, capacity(for: nil)) }
        let selection = devices.shownSyncSettings?.music ?? connected.device.effectiveSelection
        let key = MusicTabCache.Key(
            selection: selection, libraryLoad: library.loadCount, trackCount: snapshot.tracks.count,
            manifestSavedAt: devices.cardManifest?.updatedAt, manifestCount: devices.cardManifest?.entries.count,
            totalBytes: connected.volume.totalCapacity ?? 0, freeBytes: connected.volume.availableCapacity ?? 0,
            cardReadable: connected.accessURL != nil)
        let (resolved, estimate) = cache.values(for: key) {
            let resolved = SelectionResolver.resolve(selection, in: snapshot)
            return (resolved, capacity(for: resolved))
        }
        return (resolved, estimate)
    }

    /// Capacity numbers for the connected card and a selection.
    ///
    /// - Parameter resolved: The resolved selection, or `nil` before the
    ///   library has been read.
    private func capacity(for resolved: ResolvedSelection?) -> CapacityEstimate {
        CapacityEstimate.compute(totalBytes: connected.volume.totalCapacity ?? 0,
                                 freeBytes: connected.volume.availableCapacity ?? 0,
                                 manifest: devices.cardManifest,
                                 selection: resolved,
                                 cardReadable: connected.accessURL != nil)
    }
}

/// Big icon, name, firmware and capacity, like Finder's device header.
struct DeviceHeaderView: View {

    let connected: ConnectedDevice
    let devices: DeviceMonitor
    /// Switches to the Settings tab (for the firmware update link).
    var showSettings: () -> Void = {}

    @Environment(AutoSyncController.self) private var autoSync

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "ipod")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(connected.device.name).font(.title2.bold())
                Text("Shanling Q2 · \(connected.device.firmware.displayName) · \(connected.connection.label)")
                    .foregroundStyle(.secondary)
                Text(capacityText).font(.callout).foregroundStyle(.secondary)
                if let advice = devices.formatAdvice(for: connected.volume) {
                    Button(advice.summary, systemImage: "exclamationmark.triangle") {
                        showSettings()
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                    .help("See the card's format and how to fix it in Disk Utility")
                }
                if let latest = autoSync.firmware.latest,
                   autoSync.firmware.status(for: connected.device)?.shouldNotify == true {
                    Button("Q2 Pod \(latest.tag) is available", systemImage: "arrow.down.circle") { showSettings() }
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }
            Spacer()
            Button {
                Task { await autoSync.eject() }
            } label: {
                Label("Eject", systemImage: "eject")
            }
            .disabled(devices.isEjecting || autoSync.isCardBusy)
            .help(autoSync.isCardBusy ? "Q2 Sync is using the card. Wait for it to finish." : "Eject the card")
        }
    }

    /// e.g. "256 GB · 255.1 GB available".
    private var capacityText: String {
        let style = ByteCountFormatStyle(style: .file)
        let total = connected.volume.totalCapacity.map { $0.formatted(style) } ?? "Unknown size"
        let free = connected.volume.availableCapacity.map { "\($0.formatted(style)) available" } ?? ""
        return [total, free].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// The Settings tab: firmware, after-sync steps and card details.
struct DeviceSettingsView: View {

    let connected: ConnectedDevice
    let devices: DeviceMonitor

    /// Controls the "Forget this Q2?" confirmation.
    @State private var confirmingForget = false

    /// For asking notification permission when auto-sync is turned on.
    @Environment(AutoSyncController.self) private var autoSync

    var body: some View {
        ScrollViewReader { proxy in
            form
                // Scrolls to where a menu item's result appears.
                .task(id: autoSync.navigation.sectionToReveal) {
                    guard let section = autoSync.navigation.sectionToReveal else { return }
                    // Give a newly shown form a moment to lay out.
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                    withAnimation { proxy.scrollTo(section, anchor: .top) }
                    autoSync.navigation.sectionToReveal = nil
                }
        }
    }

    private var form: some View {
        Form {
            if let problem = connected.accessProblem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Grant Access…") { devices.regrantAccess() }
                }
            }

            if let advice = devices.formatAdvice(for: connected.volume) {
                CardFormatAdviceSection(advice: advice)
            }

            Section("Firmware") {
                // A Binding that reads the current firmware and writes the
                // user's choice back through the monitor (which saves it).
                Picker("Firmware", selection: Binding(
                    get: { connected.device.firmware },
                    set: { devices.setFirmware($0) })) {
                    ForEach(FirmwareKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                Text(connected.device.profile.versionLocationHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            FirmwareUpdateSection(connected: connected, devices: devices, firmware: autoSync.firmware,
                                  installer: autoSync.installer)

            Section {
                Picker("When this Q2 connects", selection: Binding(
                    get: { connected.device.effectiveAutoSync },
                    set: { mode in
                        devices.setAutoSync(mode)
                        // Notifications need permission; ask when they're first needed.
                        if mode != .off { Task { await autoSync.notifications.requestPermission() } }
                    })) {
                    ForEach(AutoSyncMode.allCases) { Text($0.title).tag($0) }
                }
                if connected.device.effectiveAutoSync != .off {
                    OpenAtLoginPrompt()
                }
            } header: {
                Text("Auto-Sync")
            } footer: {
                Text("Automatic syncs follow every safety rule. They never remove songs and never eject; if anything needs your review (the first sync, removals, songs gone from your library, a failed check), they stop, open the preview here, and notify you. Q2 Sync must be running; it stays in the menu bar when its window is closed.")
            }

            Section {
                Toggle("Add album covers", isOn: Binding(
                    get: { connected.device.effectiveAlbumCovers },
                    set: { devices.setAlbumCovers($0) }))
            } header: {
                Text("Album Covers")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Puts a cover.jpg in each album folder, made from the album's artwork in Apple Music, so the Q2 shows covers even for songs without embedded artwork. Turning it on adds covers at your next sync; turning it off removes the covers Q2 Sync added. Artwork is only read from your library, never changed, and your own cover.jpg or folder.jpg files are never touched.")
                    if connected.device.firmware == .q2Pod {
                        Text("After changing this and syncing, refresh Cover Flow on the Q2: System settings → Display → Coverflow → Refresh Coverflow, then open Cover Flow. The rebuild needs at least 16 MB free on the card.")
                    } else {
                        Text("On Shanling's firmware, covers show in Now Playing and Album Wall after you update the library on the Q2.")
                    }
                }
            }

            Section {
                Toggle("Only put new or changed playlists in the import folder", isOn: Binding(
                    get: { connected.device.effectiveImportOnlyChangedPlaylists },
                    set: { devices.setImportOnlyChangedPlaylists($0) }))
                HStack {
                    if connected.device.reimportAllPlaylists == true {
                        Label("Every playlist goes up for import at your next sync.", systemImage: "clock")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { devices.setReimportAllPlaylists(false) }
                    } else {
                        Text("After a reset or a new card, or if a playlist on the Q2 looks out of date.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Put All Up for Import") { devices.setReimportAllPlaylists(true) }
                    }
                }
                .disabled(!connected.device.effectiveImportOnlyChangedPlaylists)
            } header: {
                Text("Playlists")
            } footer: {
                Text("Off (the default): every playlist stays in the card's playlist folder, and the Q2's Import reads them all, which can take minutes. On: Import only reads new or changed playlists. Q2 Sync can't see whether you ran Import on the Q2, so when playlists from an earlier sync are still in the folder, the sync window asks, and takes them out only if you tick \u{201C}I imported them on the Q2.\u{201D} Playlists already on the Q2 stay there either way.")
            }

            PodDataSection(model: autoSync.podData, connected: connected,
                           isBlocked: autoSync.isCardInUse(except: .podData))

            Section("After Each Sync") {
                // Every step the Sync Complete window can show (it leaves
                // out playlists and covers when they don't apply).
                let steps = connected.device.profile.postSyncSteps(connection: connected.connection,
                                                                   includePlaylists: true, includeCovers: true)
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    Label(step, systemImage: "\(index + 1).circle")
                }
            }

            Section {
                LabeledContent("Format", value: connected.volume.formatDescription ?? "Unknown")
                LabeledContent("Partition Scheme",
                               value: devices.partitionScheme(for: connected.volume)?.displayName
                                   ?? (connected.connection == .q2 ? "Not visible over USB (check in a card reader)" : "Unknown"))
                LabeledContent("Card ID", value: connected.device.volumeUUID)
                    .textSelection(.enabled)
                LabeledContent("Remembered Since",
                               value: connected.device.addedDate.formatted(date: .abbreviated, time: .omitted))
                Button("Verify Card…") { autoSync.verifier.present() }
                    .disabled(connected.accessURL == nil || autoSync.isCardInUse(except: .verifier))
                    .help("Compare every song on the card with your Mac's copy and fix damaged ones")
                Button("Show Sync Logs") { SupportActions.showSyncLogs() }
                Button("Forget This Q2…", role: .destructive) { confirmingForget = true }
            } header: {
                Text("Card")
            } footer: {
                Text("Forgetting removes Q2 Sync's access to this card and its settings. Nothing on the card is changed.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Forget “\(connected.device.name)”?", isPresented: $confirmingForget) {
            Button("Forget", role: .destructive) { devices.forgetConnectedDevice() }
        } message: {
            Text("Q2 Sync will ask again the next time this card connects. Nothing on the card is changed.")
        }
    }
}

/// Warns that the card isn't one volume on Master Boot Record and explains
/// how to erase it in Disk Utility. Q2 Sync never formats a card itself.
struct CardFormatAdviceSection: View {

    let advice: CardFormatAdvice

    var body: some View {
        Section {
            Label(advice.problem, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(CardFormatAdvice.diskUtilitySteps.enumerated()), id: \.offset) { index, step in
                Label(step, systemImage: "\(index + 1).circle")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Open Disk Utility") { Self.openDiskUtility() }
        } header: {
            Text("Card Format")
        } footer: {
            Text("\(advice.consequence) Q2 Sync never erases or formats a card.")
        }
    }

    /// Opens Disk Utility (it's in /System/Applications/Utilities).
    static func openDiskUtility() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.DiskUtility") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
