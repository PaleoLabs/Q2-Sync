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

    /// The selected sidebar row. Starts on "Connect Your Q2" until a Q2
    /// has been set up on this Mac, then on Artists.
    @State private var selection: SidebarItem?

    init(library: LibraryModel, devices: DeviceMonitor) {
        self.library = library
        self.devices = devices
        _selection = State(initialValue: devices.hasKnownDevices ? .library(.artists) : .connectQ2)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                // The one-time "read-only, keep a backup" notice. It comes
                // before anything else; the setup sheet waits for it.
                .sheet(isPresented: Binding(get: { !noticeAcknowledged }, set: { _ in })) {
                    FirstLaunchNoticeView()
                }
        } detail: {
            detail
                // The sync sheet (preview, progress, result). It's attached
                // here rather than next to the new-device sheet because one
                // view should present only one sheet.
                .sheet(isPresented: Binding(get: { sync.isPresentingSheet }, set: { _ in })) {
                    SyncSheet(sync: sync, devices: devices)
                }
                // The firmware sheets, each on its own invisible view so
                // every view presents only one sheet.
                .background {
                    Color.clear.sheet(isPresented: Binding(
                        get: { autoSync.installer.isPresentingSheet && !sync.isPresentingSheet },
                        set: { if !$0 { autoSync.installer.close() } })) {
                        FirmwareInstallSheet(installer: autoSync.installer, devices: devices)
                    }
                }
                .background {
                    Color.clear.sheet(isPresented: Binding(
                        get: { autoSync.verifier.isPresentingSheet && !sync.isPresentingSheet },
                        set: { if !$0 { autoSync.verifier.close() } })) {
                        VerifyCardSheet(model: autoSync.verifier, devices: devices)
                    }
                }
                .background {
                    Color.clear.sheet(item: Binding(
                        get: { autoSync.podData.restoring.map(RestoreRequest.init) },
                        set: { if $0 == nil { autoSync.podData.restoring = nil } })) { request in
                        RestorePodDataSheet(model: autoSync.podData, backup: request.backup,
                                            deviceName: devices.connected?.device.name ?? "your Q2")
                    }
                }
                .background {
                    Color.clear.sheet(isPresented: Binding(
                        get: { noticeAcknowledged && autoSync.installer.isAskingAboutPending
                               && !autoSync.installer.isPresentingSheet && !sync.isPresentingSheet },
                        set: { _ in })) {
                        FirmwareFinishedSheet(installer: autoSync.installer, devices: devices)
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
        .sheet(item: Binding(get: { noticeAcknowledged && !autoSync.installer.isBusy ? devices.pendingVolume : nil },
                             set: { devices.pendingVolume = $0 })) { volume in
            NewDeviceSheet(volume: volume, devices: devices)
        }
        .alert("Something Went Wrong",
               isPresented: Binding(get: { devices.errorMessage != nil },
                                    set: { if !$0 { devices.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(devices.errorMessage ?? "")
        }
        // Select the Q2 automatically when it connects, like Finder does.
        .onChange(of: devices.connected?.device.volumeUUID) { _, uuid in
            if let uuid { selection = .device(uuid: uuid) }
            else if case .device = selection { selection = .connectQ2 }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Devices") {
                if let connected = devices.connected {
                    DeviceSidebarRow(connected: connected, devices: devices)
                        .tag(SidebarItem.device(uuid: connected.device.volumeUUID))
                } else {
                    Label("Connect Your Q2", systemImage: "cable.connector")
                        .foregroundStyle(.secondary)
                        .tag(SidebarItem.connectQ2)
                }
                // Other mounted cards already set up as a Q2. One card is
                // shown at a time; clicking another switches to it (not
                // while a sync or check is using the current card).
                ForEach(devices.otherKnownVolumes) { volume in
                    Button {
                        devices.switchTo(volume)
                    } label: {
                        Label(volume.name, systemImage: "ipod")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(autoSync.isCardBusy)
                    .help("Show “\(volume.name)”")
                    .selectionDisabled()
                }
                // A drive waiting to be set up: the whole row is the button
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Set up “\(volume.name)” as your Q2's card")
                    .selectionDisabled()
                }
            }

            Section("Music Library") {
                ForEach(BrowseCategory.allCases) { item in
                    Label(item.rawValue, systemImage: item.symbolName)
                        .tag(SidebarItem.library(item))
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        .safeAreaInset(edge: .bottom) {
            LibraryStatusView(library: library)
                .padding(10)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
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
        .frame(width: 1000, height: 600)
}
