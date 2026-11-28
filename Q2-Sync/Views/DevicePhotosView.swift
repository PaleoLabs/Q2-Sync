//
//  DevicePhotosView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The Q2's Photos tab, shaped like Finder's iPod Photos tab: "Sync photos
//  onto <Q2>", where from (the Photos library; a chosen folder comes
//  later), all photos and albums or only the ticked ones, "Only
//  favorites", "Automatically include photos from", "Include
//  full-resolution photos", and the albums list.
//
//  HOW IT FITS
//  Shown by `DeviceView`. Changes are edits until Apply (the Sync bar
//  below every tab). Albums come from `PhotoLibraryModel`, access from
//  `PhotosAccess`. The list's order: Favorites, Recently Added, Media
//  Types, Hidden, then your own albums (folders flattened, the folder
//  shown under the title). "All photos and albums" ticks your own albums
//  only, plus photos in no album (loose in Photos/, so All Photos on the
//  Q2 shows everything). PhotoKit can't read People or Recently Deleted.
//  Photos need Q2 Pod; on stock firmware the tab says so.
//

import AppKit
import SwiftUI

struct DevicePhotosView: View {

    let connected: ConnectedDevice
    let devices: DeviceMonitor

    @Environment(AutoSyncController.self) private var autoSync

    @State private var searchText = ""

    private var model: PhotoLibraryModel { autoSync.photos }
    private var access: PhotosAccess { autoSync.photosAccess }

    private var settings: PhotoSelection {
        devices.shownSyncSettings?.photos ?? connected.device.effectivePhotos
    }

    var body: some View {
        Group {
            if connected.device.profile.photosFolderName == nil {
                ContentUnavailableView {
                    Label("Photo Sync Needs Q2 Pod", systemImage: "photo.on.rectangle")
                } description: {
                    Text("Shanling's firmware has no photo viewer, so Q2 Sync only syncs photos to a Q2 running Q2 Pod.")
                }
            } else {
                switch access.status {
                case .notAllowed:
                    ContentUnavailableView {
                        Label("Photos from Your Photos Library", systemImage: "photo.on.rectangle")
                    } description: {
                        Text("To list your albums, allow Q2 Sync to read your Photos library. It only reads it, and never changes your photos.")
                    } actions: {
                        Button("Allow Access to Photos…") { Task { await model.allowAccess() } }
                            .buttonStyle(.borderedProminent)
                    }
                case .denied:
                    ContentUnavailableView {
                        Label("Q2 Sync Can't Read Your Photos", systemImage: "photo.on.rectangle")
                    } description: {
                        Text("Access to Photos was turned off. Turn on Q2 Sync in System Settings › Privacy & Security › Photos, then come back here.")
                    } actions: {
                        Button("Open Privacy Settings…") { access.openPrivacySettings() }
                        Button("Check Again") { Task { await model.load() } }
                    }
                case .allowed:
                    albumsView
                }
            }
        }
        .task { await model.load() }
    }

    // MARK: - Albums

    @ViewBuilder
    private var albumsView: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Reading your Photos library…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Your Photos Library Couldn't Be Read", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await model.load() } }
            }
        case .loaded(let library):
            VStack(spacing: 0) {
                header
                VStack(spacing: 0) {
                    HStack {
                        Text("Albums").font(.headline)
                        Spacer()
                        FilterTextField(text: $searchText, prompt: "Search Albums", field: .photosTab)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    Divider()
                    albumList(library)
                }
                // Like Finder: photos off dims everything below the box.
                .disabled(!settings.isEnabled)
                Divider()
                footer(library)
            }
        }
    }

    /// "Sync photos onto [Q2]", source, all or selected, and the options.
    private var header: some View {
        SyncSectionHeader(
            title: "Sync photos onto \(connected.device.name)",
            isEnabled: Binding(get: { settings.isEnabled },
                               set: { on in devices.editSyncSettings { $0.photos.isEnabled = on } }),
            choice: Binding(get: { settings.includesAll },
                            set: { all in devices.editSyncSettings { $0.photos.includesAll = all } }),
            options: [
                SyncChoiceOption(label: "All photos and albums", value: true),
                SyncChoiceOption(label: "Selected albums", value: false),
            ]) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Copy photos from:")
                    sourceMenu
                }
                Picker("Automatically include photos from:", selection: Binding(
                    get: { settings.recentWindow },
                    set: { window in devices.editSyncSettings { $0.photos.recentWindow = window } })) {
                    Text("No photos").tag(PhotoRecentWindow?.none)
                    Divider()
                    ForEach(PhotoRecentWindow.allCases, id: \.self) { window in
                        Text(window.title.prefix(1).uppercased() + window.title.dropFirst())
                            .tag(PhotoRecentWindow?.some(window))
                    }
                }
                .fixedSize()
                .disabled(settings.includesAll)
                .help("Under Selected albums, also copies photos taken in this period, loose in the Photos folder (All Photos on the Q2), unless a ticked album already has them.")
                Toggle("Only favorites", isOn: Binding(
                    get: { settings.onlyFavorites },
                    set: { on in devices.editSyncSettings { $0.photos.onlyFavorites = on } }))
                    .toggleStyle(.checkbox)
                    .help("Copies only photos marked as favorites, within the albums chosen.")
                Toggle("Include full-resolution photos", isOn: Binding(
                    get: { settings.fullResolution },
                    set: { on in devices.editSyncSettings { $0.photos.fullResolution = on } }))
                    .toggleStyle(.checkbox)
                    .help("Copies each photo at its full size (as JPEG) instead of a copy sized for the Q2's screen. Uses far more space, and big photos open slowly on the Q2. Changing this replaces the photos on the card at the next sync.")
            }
            .padding(.leading, 22)
            .disabled(!settings.isEnabled)
            if !settings.isEnabled && hasQ2SyncPhotos {
                SyncSectionNote(text: "Photos are off. When you sync, the review lets you remove the photos Q2 Sync put on this card.",
                                systemImage: "exclamationmark.triangle", color: .orange)
            } else if access.status == .allowed(limited: true) {
                HStack {
                    SyncSectionNote(text: "Q2 Sync can only see the photos you picked for it.",
                                    systemImage: "info.circle")
                    Button("Change…") { access.openPrivacySettings() }
                }
            } else {
                Text("Photos are copied sized for the Q2's screen, without location data. The Q2 shows up to 500 photos per album, and in All Photos.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("People and Recently Deleted can't be read by other apps, so they aren't listed. Q2 Sync never changes your Photos library.")
            }
        }
    }

    /// Where photos come from. Only the Photos library for now. A pop-up
    /// menu like Finder's: Photos with its app icon and a tick, then
    /// "Choose Folder…" (not yet available, so it can't be picked).
    private var sourceMenu: some View {
        Picker("Copy photos from:", selection: .constant(0)) {
            Label { Text("Photos") } icon: { Image(nsImage: Self.photosAppIcon) }
                .tag(0)
            Divider()
            Text("Choose Folder… (Coming Later)")
                .tag(1)
                .selectionDisabled()
        }
        .labelsHidden()
        .fixedSize()
        .help("Copying photos from a folder instead of your Photos library is planned for a later version.")
    }

    /// The Photos app's icon at menu size (a generic photo icon if Photos
    /// can't be found).
    private static let photosAppIcon: NSImage = {
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Photos")
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: nil)
            ?? NSImage()
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }()

    /// `true` if the card holds photos Q2 Sync copied there.
    private var hasQ2SyncPhotos: Bool {
        !(devices.cardManifest?.photos?.isEmpty ?? true)
    }

    private func albumList(_ library: PhotoLibraryContents) -> some View {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let shown = query.isEmpty ? library.albums : library.albums.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.folderPath.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        let special = shown.filter { [.favorites, .recentlyAdded].contains($0.kind) }
        let mediaTypes = shown.filter { $0.kind == .mediaType }
        let hidden = shown.filter { $0.kind == .hidden }
        let user = shown.filter { $0.kind == .user }
        return Group {
            if shown.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("No Albums", systemImage: "photo.on.rectangle",
                                           description: Text(settings.includesAll
                                                             ? "Every photo in your library is copied, loose in the Photos folder."
                                                             : "Make albums in Photos to choose what to copy."))
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                List {
                    ForEach(special) { row($0, in: shown) }
                    if !mediaTypes.isEmpty {
                        DisclosureGroup("Media Types") {
                            ForEach(mediaTypes) { row($0, in: mediaTypes) }
                        }
                    }
                    ForEach(hidden) { row($0, in: shown) }
                    if !user.isEmpty {
                        Section("My Albums") {
                            ForEach(user) { row($0, in: user) }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private func row(_ album: PhotoAlbum, in group: [PhotoAlbum]) -> some View {
        PhotoAlbumRow(album: album, settings: settings) { ticked in
            // ⌘-click: every album in this group takes the box's new state.
            let isForAll = NSApp.currentEvent?.modifierFlags.contains(.command) == true
            let ids = isForAll ? Set(group.map(\.id)) : [album.id]
            devices.editSyncSettings { $0.photos.setTicked(ticked, ids: ids) }
        }
    }

    private func footer(_ library: PhotoLibraryContents) -> some View {
        let wanted = PhotoPlanner.wantedKeys(library: library, selection: settings) ?? [:]
        let bytes = wanted.values.reduce(UInt64(0)) {
            $0 + PhotoPlanner.estimatedCardSize(for: $1, fullResolution: settings.fullResolution)
        }
        return HStack(spacing: 12) {
            Image(systemName: "photo").foregroundStyle(.secondary)
            Text(pluralized(wanted.count, "photo")).fontWeight(.medium)
            Text("about " + Int64(bytes).formatted(ByteCountFormatStyle(style: .file)))
                .foregroundStyle(.secondary)
                .help("Sizes are estimated: the copies are made as they're written to the card.")
            Spacer()
            Text("\(pluralized(library.assets.count, "photo")) in your library")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// An album: tick box, title (and the Photos folder it's in), photo count.
private struct PhotoAlbumRow: View {

    let album: PhotoAlbum
    let settings: PhotoSelection
    let setTicked: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { settings.isTicked(album) }, set: setTicked))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(settings.includesAll)
            Image(systemName: album.kind.symbolName).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title).lineLimit(1)
                if !album.folderPath.isEmpty {
                    Text(album.folderPath.joined(separator: " › "))
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if album.assetIDs.count > PhotoPlanner.maximumPerGrid {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help("The Q2 shows only the first \(PhotoPlanner.maximumPerGrid) photos of an album. All are copied.")
            }
            Text(pluralized(album.assetIDs.count, "photo"))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 1)
        .help(album.kind == .hidden ? "Hidden photos are copied only when you tick this album." : "")
    }
}
