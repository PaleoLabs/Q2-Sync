//
//  RootView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The main window: a Finder-style sidebar with a "Devices" section (your
//  Q2, with an Eject button) and a "Library" section (Artists, Albums,
//  Genres, Playlists), plus the detail area for whatever is selected.
//
//  HOW IT FITS
//  Owns no data itself. It reads `LibraryModel` and `DeviceMonitor` and
//  shows `DeviceView`, `LibraryCategoryView` or `NewDeviceSheet`.
//

import SwiftUI

/// Something that can be selected in the sidebar.
///
/// An `enum` with associated values lets one selection variable hold
/// either a device (by UUID) or a library category.
enum SidebarItem: Hashable {
    case device(uuid: String)
    /// "Connect Your Q2", while no Q2 is connected.
    case connectQ2
    case library(BrowseCategory)
}

/// The app's main window content.
struct RootView: View {

    let library: LibraryModel
    let devices: DeviceMonitor

    /// The sync coordinator, provided by `Q2SyncApp` via the environment.
    @Environment(SyncCoordinator.self) private var sync

    /// For the firmware sheets.
    @Environment(AutoSyncController.self) private var autoSync

    /// `true` once the one-time first-launch notice has been acknowledged.
    @AppStorage(FirstLaunchNoticeView.acknowledgedKey) private var noticeAcknowledged = false

    var body: some View {
        // The sidebar can't be hidden (see `PinnedSidebar`).
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
                .toolbar(removing: .sidebarToggle)
                .background(PinnedSidebar())
                // The one-time "read-only, keep a backup" notice. It comes
                // before anything else; the setup sheet waits for it.
                .sheet(isPresented: Binding(get: { !noticeAcknowledged }, set: { _ in })) {
                    FirstLaunchNoticeView()
                }
                // Room for long card names, without crowding out the page.
                // Keep this last: under `safeAreaInset` it was ignored.
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 320)
        } detail: {
            detail
                // The sync sheet (preview, progress, result). It's attached
                // here rather than next to the new-device sheet because one
                // view should present only one sheet.
                .sheet(isPresented: Binding(get: { sync.isPresentingSheet }, set: { _ in })) {
                    SyncSheet(sync: sync, devices: devices)
                        .deviceErrorAlert(devices) { sync.isPresentingSheet }
                }
                // The firmware sheets, each on its own invisible view so
                // every view presents only one sheet.
                .background {
                    Color.clear.sheet(isPresented: Binding(
                        get: { autoSync.installer.isPresentingSheet && !sync.isPresentingSheet },
                        set: { if !$0 { autoSync.installer.close() } })) {
                        FirmwareInstallSheet(installer: autoSync.installer, devices: devices)
                            .deviceErrorAlert(devices) { autoSync.installer.isPresentingSheet }
                    }
                }
                .background {
                    Color.clear.sheet(isPresented: Binding(
                        get: { autoSync.verifier.isPresentingSheet && !sync.isPresentingSheet },
                        set: { if !$0 { autoSync.verifier.close() } })) {
                        VerifyCardSheet(model: autoSync.verifier, devices: devices)
                            .deviceErrorAlert(devices) { autoSync.verifier.isPresentingSheet }
                    }
                }
                .background {
                    Color.clear.sheet(item: Binding(
                        get: { autoSync.podData.restoring.map(RestoreRequest.init) },
                        set: { if $0 == nil { autoSync.podData.restoring = nil } })) { request in
                        RestorePodDataSheet(model: autoSync.podData, backup: request.backup,
                                            deviceName: devices.connected?.device.name ?? "your Q2")
                            .deviceErrorAlert(devices) { autoSync.podData.restoring != nil }
                    }
                }
                .background {
                    Color.clear.sheet(isPresented: Binding(
                        get: { isAskingAboutPendingFirmware },
                        set: { _ in })) {
                        FirmwareFinishedSheet(installer: autoSync.installer, devices: devices)
                            .deviceErrorAlert(devices) { isAskingAboutPendingFirmware }
                    }
                }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await library.load() }
                } label: {
                    Label("Refresh Library", systemImage: "arrow.clockwise")
                }
                // Text beside the icon: a bare circle arrow was ambiguous.
                .labelStyle(.titleAndIcon)
                .disabled(library.state == .loading)
                .help(LibraryWording.refreshHelp)
            }
        }
        // Read the Music library the first time the window is shown (once
        // the first-launch notice is accepted), so the views have something
        // to show. Not at app launch: Q2 Sync may run in the menu bar for
        // days without the window open. The Q2 connecting also reads it
        // (see `AutoSyncController`).
        .task(id: noticeAcknowledged) {
            if noticeAcknowledged && library.state == .idle {
                await library.load()
            }
        }
        // The "Is this your Q2?" sheet appears whenever a new drive is pending.
        // `Binding(get:set:)` adapts the optional volume to the sheet's
        // `item:` parameter.
        .sheet(item: Binding(get: { volumeToSetUp },
                             set: { devices.pendingVolume = $0 })) { volume in
            NewDeviceSheet(volume: volume, devices: devices)
                .deviceErrorAlert(devices) { volumeToSetUp != nil }
        }
        .deviceErrorAlert(devices) { !isSheetShowingDeviceError }
        // Select the Q2 automatically when it connects, like Finder does.
        .onChange(of: devices.connected?.device.volumeUUID) { _, uuid in
            autoSync.navigation.deviceChanged(to: uuid)
        }
        .onAppear {
            autoSync.navigation.reconcile(connected: devices.connected?.device.volumeUUID)
        }
    }

    /// `true` while "Did the Firmware Update Finish?" should be showing.
    private var isAskingAboutPendingFirmware: Bool {
        noticeAcknowledged && autoSync.installer.isAskingAboutPending
            && !autoSync.installer.isPresentingSheet && !sync.isPresentingSheet
    }

    /// The drive the "Is this your Q2?" sheet should be asking about.
    private var volumeToSetUp: VolumeInfo? {
        noticeAcknowledged && !autoSync.installer.isBusy ? devices.pendingVolume : nil
    }

    /// `true` while a sheet that presents the device error alert itself is
    /// open: every sheet but the first-launch notice, when there's no card to
    /// have errors about. The window's own alert stays out of the way then.
    private var isSheetShowingDeviceError: Bool {
        sync.isPresentingSheet || autoSync.installer.isPresentingSheet
            || autoSync.verifier.isPresentingSheet || autoSync.podData.restoring != nil
            || isAskingAboutPendingFirmware || volumeToSetUp != nil
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        @Bindable var navigation = autoSync.navigation
        return List(selection: $navigation.selection) {
            Section("Devices") {
                if let connected = devices.connected {
                    DeviceSidebarRow(connected: connected, devices: devices)
                        .tag(SidebarItem.device(uuid: connected.device.volumeUUID))
                } else {
                    Label("Connect Your Q2", systemImage: "cable.connector")
                        .foregroundStyle(.secondary)
                        .tag(SidebarItem.connectQ2)
                }
                // Other set-up cards and drives waiting to be set up, all in
                // ONE row that is always there (zero height when empty).
                // Adding a row to the sidebar while a sync sheet was open
                // blanked the whole list until the sheet closed; changing
                // what's inside an existing row doesn't, so plugging in or
                // ejecting another drive mid-sync shows up at once.
                OtherDrivesSidebarRow(devices: devices, isCardBusy: autoSync.isCardBusy)
                    .listRowInsets(EdgeInsets())
                    .selectionDisabled()
            }

            Section("Music Library") {
                ForEach(BrowseCategory.allCases) { item in
                    Label(item.rawValue, systemImage: item.symbolName)
                        .tag(SidebarItem.library(item))
                }
            }
        }
        // Lets the other-drives row shrink to nothing when it's empty.
        .environment(\.defaultMinListRowHeight, 0)
        .safeAreaInset(edge: .bottom) {
            LibraryStatusView(library: library)
                .padding(10)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch autoSync.navigation.selection {
        case .device:
            if let connected = devices.connected {
                DeviceView(connected: connected, devices: devices, library: library)
            } else {
                ConnectQ2View(hasSetUpBefore: devices.hasKnownDevices,
                          waitingDrives: devices.postponedVolumes.map(\.name))
            }
        case .connectQ2:
            ConnectQ2View(hasSetUpBefore: devices.hasKnownDevices,
                          waitingDrives: devices.postponedVolumes.map(\.name))
        case .library(let category):
            LibraryCategoryView(library: library, devices: devices, category: category)
        case nil:
            ContentUnavailableView("Nothing Selected", systemImage: "sidebar.left")
        }
    }
}

/// The sidebar lines for other mounted Q2 cards (click to switch) and
/// drives waiting to be set up (click to set up), stacked inside a single
/// list row. See the note where it's used for why it's one row.
private struct OtherDrivesSidebarRow: View {
    let devices: DeviceMonitor
    /// Switching cards isn't allowed while a sync or check uses the card.
    let isCardBusy: Bool

    /// Roughly a sidebar row's height, so the lines line up with real rows.
    private let lineHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Other mounted cards already set up as a Q2. One card is
            // shown at a time; clicking another switches to it.
            ForEach(devices.otherKnownVolumes) { volume in
                Button {
                    devices.switchTo(volume)
                } label: {
                    Label(volume.name, systemImage: "ipod")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: lineHeight, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isCardBusy)
                .help("Show “\(volume.name)”")
            }
            // A drive waiting to be set up: the whole line is the button
            // (a small "Set Up…" alone was hard to hit), and "Set Up…"
            // never shrinks, so it isn't cut off.
            ForEach(devices.postponedVolumes) { volume in
                Button {
                    devices.setUp(volume)
                } label: {
                    HStack {
                        Label(volume.name, systemImage: "externaldrive.badge.questionmark")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        Text("Set Up…")
                            .font(.callout)
                            .foregroundStyle(.tint)
                            .fixedSize()
                    }
                    .frame(minHeight: lineHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Set up “\(volume.name)” as your Q2's card")
            }
        }
        // No extra padding: with the row's insets removed (so an empty
        // row takes no space), the sidebar already lines these up with
        // the rows above and below.
    }
}

extension View {

    /// The "Something Went Wrong" alert for `DeviceMonitor.errorMessage`.
    ///
    /// An alert waits behind a sheet attached to the same window, so each
    /// sheet presents it itself, and the window only while none is open.
    ///
    /// - Parameter isActive: Whether this view is the one to show it. It's
    ///   read live: a sheet that's closing must neither show the error nor
    ///   clear it, so the window can show it next.
    func deviceErrorAlert(_ devices: DeviceMonitor,
                          isActive: @escaping @MainActor () -> Bool) -> some View {
        modifier(DeviceErrorAlert(devices: devices, isActive: isActive))
    }
}

/// Backs `deviceErrorAlert`.
///
/// A `ViewModifier` so that the error is read in a `body` of its own: a
/// change then redraws the view presenting the alert, without relying on a
/// `.sheet`'s content closure being run again.
private struct DeviceErrorAlert: ViewModifier {

    let devices: DeviceMonitor
    let isActive: @MainActor () -> Bool

    func body(content: Content) -> some View {
        let message = devices.errorMessage
        content.alert("Something Went Wrong",
                      isPresented: Binding(get: { isActive() && devices.errorMessage != nil },
                                           set: { if !$0 && isActive() { devices.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}

/// A backup to restore, made `Identifiable` for `.sheet(item:)`.
private struct RestoreRequest: Identifiable {
    let backup: PodDataBackupInfo
    var id: String { backup.folder?.path ?? backup.created.description }
}

/// The Q2's row in the sidebar, with an Eject button like Finder's.
struct DeviceSidebarRow: View {

    let connected: ConnectedDevice
    let devices: DeviceMonitor
    @Environment(AutoSyncController.self) private var autoSync

    var body: some View {
        row
            .contextMenu {
                Button("Sync Now") { Task { await autoSync.startSync(automatic: false) } }
                    .disabled(!autoSync.canStartCardOperation)
                Button("Eject") { Task { await autoSync.eject() } }
                    .disabled(devices.isEjecting || autoSync.isCardBusy)
                Divider()
                Button("Show in Finder") { SupportActions.showCardInFinder(connected) }
                    .disabled(devices.isEjecting)
            }
    }

    private var row: some View {
        HStack {
            Label {
                Text(connected.device.name)
            } icon: {
                Image(systemName: "ipod")
            }
            Spacer()
            if devices.isEjecting {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await autoSync.eject() }
                } label: {
                    Image(systemName: "eject.fill")
                }
                .buttonStyle(.borderless)
                .disabled(autoSync.isCardBusy)
                .help("Eject “\(connected.device.name)”")
            }
        }
    }
}

#Preview {
    let library = LibraryModel(source: FixtureLibrarySource.preview)
    let devices = DeviceMonitor()
    let sync = SyncCoordinator()
    RootView(library: library, devices: devices)
        .environment(sync)
        .environment(AutoSyncController(library: library, devices: devices, sync: sync))
        .frame(width: 1100, height: 600)
}
