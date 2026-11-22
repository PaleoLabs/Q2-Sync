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

    /// The selected sidebar row.
    @State private var selection: SidebarItem? = .library(.artists)

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
                    Label("Refresh Music Library", systemImage: "arrow.clockwise")
                }
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
            else if case .device = selection { selection = .library(.artists) }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            if devices.connected != nil || !devices.postponedVolumes.isEmpty {
                Section("Devices") {
                    if let connected = devices.connected {
                        DeviceSidebarRow(connected: connected, devices: devices)
                            .tag(SidebarItem.device(uuid: connected.device.volumeUUID))
                    }
                    ForEach(devices.postponedVolumes) { volume in
                        HStack {
                            Label(volume.name, systemImage: "externaldrive.badge.questionmark")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Set Up…") { devices.setUp(volume) }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                        .selectionDisabled()
                    }
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
                ContentUnavailableView("Q2 Not Connected", systemImage: "ipod",
                                       description: Text("Set the Q2's USB switch to USB Storage and connect it."))
            }
        case .library(let category):
            LibraryCategoryView(library: library, category: category)
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
