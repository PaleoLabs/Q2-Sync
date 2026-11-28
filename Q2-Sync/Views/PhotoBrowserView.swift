//
//  PhotoBrowserView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The sidebar's Photos › Albums page: the Photos library's albums on the
//  left (All Photos, Favorites, Recently Added, Media Types, Hidden, then
//  your own albums), the chosen album's photos on the right (name, date,
//  size, favourite), and where each photo stands with the Q2: on it,
//  copied at the next sync, or not chosen. From the Mac-side record of the
//  card, so it works while the Q2 is unplugged. The toolbar's search field
//  narrows the photos by file name; Photo Info (⌘I) shows the selected
//  photo with a small preview. Read-only; choosing albums happens on the
//  Q2's Photos tab.
//
//  HOW IT FITS
//  Shown by `RootView` when Albums is selected. The sidebar section shows
//  while any Q2 syncs photos (#68). Built from the template of
//  `PodcastBrowserView`; the marks come from `PhotoMarks`.
//

import AppKit
import SwiftUI

extension FocusedValues {
    /// `true` when the frontmost window shows the Albums browser (read by
    /// `SongInfoCommands` to offer Show Photo Info).
    @Entry var offersPhotoInfo: Bool?
}

/// Browses the Photos library's albums and photos against the Q2.
struct PhotoBrowserView: View {

    let devices: DeviceMonitor

    @Environment(AutoSyncController.self) private var autoSync

    /// The album shown on the right; `nil` is All Photos.
    @State private var albumID: PhotoAlbum.ID?

    /// The selected photos.
    @State private var selection: Set<PhotoAsset.ID> = []

    /// Column sorting; oldest first, like Photos.
    @State private var sortOrder = [KeyPathComparator(\PhotoAsset.created)]

    /// Whether the photo inspector is open (remembered across launches).
    @AppStorage("showPhotoInfo") private var showPhotoInfo = false

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private var model: PhotoLibraryModel { autoSync.photos }

    var body: some View {
        Group {
            switch model.access.status {
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
                    Button("Open Privacy Settings…") { model.access.openPrivacySettings() }
                    Button("Check Again") { Task { await model.load() } }
                }
            case .allowed:
                content
            }
        }
        .navigationTitle("Albums")
        .navigationSubtitle(comparisonSubtitle)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search Photos")
        .searchFocused($isSearchFocused)
        // Edit › Find (⌘F) puts the cursor in the search field.
        .onAppear { autoSync.navigation.filterAppeared(.library) }
        .onDisappear { autoSync.navigation.filterDisappeared(.library) }
        .onChange(of: autoSync.navigation.findRequests) {
            if autoSync.navigation.filterField == .library { isSearchFocused = true }
        }
        // Read once; Refresh Photos reads again (a big library is slow).
        .task { if model.contents == nil { await model.load() } }
        .onChange(of: albumID) { selection = [] }
        // Enables View › Show Photo Info while this view is showing.
        .focusedSceneValue(\.offersPhotoInfo, true)
        .inspector(isPresented: $showPhotoInfo) {
            let photo = selection.count == 1 ? model.contents?.assetsByID[selection.first ?? ""] : nil
            PhotoInspectorView(photo: photo, selectedCount: selection.count,
                               placement: photo.flatMap { marks?.placement(of: $0) },
                               albums: photo.map { albumTitles(of: $0) } ?? [])
                .inspectorColumnWidth(min: 220, ideal: 260, max: 300)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $showPhotoInfo) {
                    Label("Photo Info", systemImage: "info.circle")
                }
                .labelStyle(.titleAndIcon)
                .help("Show or hide details of the selected photo (⌘I)")
            }
        }
    }

    /// The Q2 compared with, and its photos.
    private var marks: PhotoMarks? {
        guard let library = model.contents else { return nil }
        let reference = devices.referenceContents
        return PhotoMarks(record: reference?.record, selection: reference?.device.effectivePhotos,
                          library: library)
    }

    /// The user albums a photo is in, for the info panel.
    private func albumTitles(of photo: PhotoAsset) -> [String] {
        (model.contents?.albums ?? []).filter { $0.kind == .user && $0.assetIDs.contains(photo.id) }
            .map { ($0.folderPath + [$0.title]).joined(separator: " › ") }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
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
        case .loaded(let library) where library.isEmpty:
            ContentUnavailableView {
                Label("No Photos", systemImage: "photo.on.rectangle")
            } description: {
                Text("Your Photos library has no photos Q2 Sync can read. Videos aren't synced yet.")
            } actions: {
                Button("Check Again") { Task { await model.load() } }
            }
        case .loaded(let library):
            let marks = marks
            HSplitView {
                albumList(library, marks: marks)
                    .frame(minWidth: 180, idealWidth: 230, maxWidth: 360)
                photos(library, marks: marks)
                    .frame(minWidth: 360, maxWidth: .infinity)
            }
        }
    }

    /// All Photos, the Photos library's own albums, then the user's.
    private func albumList(_ library: PhotoLibraryContents, marks: PhotoMarks?) -> some View {
        let assets = library.assetsByID
        let special = library.albums.filter { [.favorites, .recentlyAdded].contains($0.kind) }
        let mediaTypes = library.albums.filter { $0.kind == .mediaType }
        let hidden = library.albums.filter { $0.kind == .hidden }
        let user = library.albums.filter { $0.kind == .user }
        let selection = devices.referenceContents?.device.effectivePhotos
        func row(_ album: PhotoAlbum) -> some View {
            PhotoBrowserAlbumRow(title: album.title, symbol: album.kind.symbolName,
                                 folderPath: album.folderPath,
                                 count: album.assetIDs.count,
                                 onQ2: marks?.onQ2Count(of: album.assetIDs.compactMap { assets[$0] }),
                                 isChosen: selection.map { $0.isEnabled && $0.isTicked(album) } ?? false)
                .tag(Optional(album.id))
        }
        return List(selection: $albumID) {
            PhotoBrowserAlbumRow(title: "All Photos", symbol: "photo.on.rectangle",
                                 folderPath: [], count: library.assets.count,
                                 onQ2: marks?.onQ2Count(of: library.assets),
                                 isChosen: selection.map { $0.isEnabled && $0.includesAll } ?? false)
                .tag(PhotoAlbum.ID?.none)
            ForEach(special) { row($0) }
            if !mediaTypes.isEmpty {
                DisclosureGroup("Media Types") {
                    ForEach(mediaTypes) { row($0) }
                }
            }
            ForEach(hidden) { row($0) }
            if !user.isEmpty {
                Section("My Albums") {
                    ForEach(user) { row($0) }
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// The chosen album's photos, narrowed by the search field.
    @ViewBuilder
    private func photos(_ library: PhotoLibraryContents, marks: PhotoMarks?) -> some View {
        let assets = library.assetsByID
        let album = albumID.flatMap { id in library.albums.first { $0.id == id } }
        let inAlbum = album.map { $0.assetIDs.compactMap { assets[$0] } }
            ?? library.assets.filter { !$0.isHidden } // All Photos leaves Hidden out, like Photos.
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let shown = (query.isEmpty ? inAlbum : inAlbum.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
        }).sorted(using: sortOrder)
        if shown.isEmpty {
            if query.isEmpty {
                ContentUnavailableView("No Photos", systemImage: "photo",
                                       description: Text("This album is empty."))
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        } else {
            VStack(spacing: 0) {
                table(shown, marks: marks)
                if let album, album.assetIDs.count > PhotoPlanner.maximumPerGrid {
                    Divider()
                    Label("The Q2 shows only the first \(PhotoPlanner.maximumPerGrid) photos of an album. All are copied.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    private func table(_ photos: [PhotoAsset], marks: PhotoMarks?) -> some View {
        Table(photos, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.displayName, comparator: .localizedStandard) { photo in
                HStack(spacing: 4) {
                    Text(photo.displayName).help(photo.displayName)
                    if photo.isFavorite {
                        Image(systemName: "heart.fill").foregroundStyle(.secondary)
                            .help("A favourite in Photos")
                    }
                }
            }
            .width(min: 140, ideal: 220)
            TableColumn("Date", value: \.created) { photo in
                Text(photo.created.formatted(date: .abbreviated, time: .shortened))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150, max: 180)
            TableColumn("Size", value: \.pixelCount) { photo in
                Text("\(photo.pixelWidth) × \(photo.pixelHeight)")
                    .monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 100, max: 120)
            TableColumn("Q2") { photo in
                PhotoStatusLabel(placement: marks?.placement(of: photo))
            }
            .width(min: 100, ideal: 130)
        }
        .contextMenu(forSelectionType: PhotoAsset.ID.self) { ids in
            Button("Show Info") {
                selection = ids
                showPhotoInfo = true
            }
            .disabled(ids.isEmpty)
        } primaryAction: { ids in
            // Double-click, like the song, book and episode tables.
            selection = ids
            showPhotoInfo.toggle()
        }
    }

    /// "Compared with Shanling-Q2 · as of Nov 22, 10:14", or a hint.
    private var comparisonSubtitle: String {
        guard case .loaded = model.state else { return "" }
        guard let reference = devices.referenceContents, reference.record.photoAssetIDs != nil else {
            return "Connect your Q2 to see which photos are on it"
        }
        let when = reference.record.checkedAt.formatted(date: .abbreviated, time: .shortened)
        return devices.connected?.device.volumeUUID == reference.device.volumeUUID
            ? "Compared with \(reference.device.name)"
            : "Compared with \(reference.device.name) · as of \(when)"
    }
}

/// One album in the browser's list: icon, title (and its Photos folder),
/// how many photos and how many are on the Q2.
private struct PhotoBrowserAlbumRow: View {
    let title: String
    let symbol: String
    let folderPath: [String]
    let count: Int
    /// Photos of it on the Q2, or `nil` without a Q2.
    let onQ2: Int?
    /// Chosen on the Q2's Photos tab.
    let isChosen: Bool

    var body: some View {
        HStack(spacing: 6) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1)
                    if !folderPath.isEmpty {
                        Text(folderPath.joined(separator: " › "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } icon: {
                Image(systemName: symbol)
            }
            Spacer(minLength: 4)
            if isChosen {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .help("Chosen on the Q2's Photos tab.")
            }
            Text(onQ2.map { "\($0.formatted()) of \(count.formatted())" } ?? count.formatted())
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .help(onQ2 == nil ? "Photos in this album." : "Photos of this album on the Q2, of all its photos.")
        }
    }
}

/// A photo's place with the Q2.
struct PhotoStatusLabel: View {
    let placement: TrackPlacement?

    var body: some View {
        switch placement {
        case .onQ2:
            Label("On Q2", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .nextSync:
            Label("Next sync", systemImage: "arrow.down.circle").foregroundStyle(.secondary)
                .help("Copied to the Q2 at the next sync.")
        case .notChosen:
            Label("Not chosen", systemImage: "minus.circle").foregroundStyle(.secondary)
                .help("Not chosen on the Q2's Photos tab.")
        case .cantSync, nil:
            EmptyView()
        }
    }
}

/// The Photo Info panel: a preview of the selected photo, where it stands
/// with the Q2, its date, size and albums. Read-only.
struct PhotoInspectorView: View {

    /// The selected photo, or `nil` for none or several.
    let photo: PhotoAsset?
    let selectedCount: Int
    let placement: TrackPlacement?
    /// The user albums it's in.
    let albums: [String]

    @State private var preview: NSImage?

    var body: some View {
        if let photo {
            details(photo)
                .task(id: photo.id) {
                    preview = nil
                    preview = await PhotoKitSource.thumbnail(for: photo.id, side: 240)
                }
        } else {
            ContentUnavailableView(selectedCount > 1 ? "\(selectedCount) Photos Selected" : "No Photo Selected",
                                   systemImage: "info.circle",
                                   description: Text("Select one photo to see its details."))
        }
    }

    private func details(_ photo: PhotoAsset) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Group {
                    if let preview {
                        Image(nsImage: preview).resizable().scaledToFit()
                    } else {
                        Rectangle().fill(.quaternary)
                            .aspectRatio(CGFloat(max(photo.pixelWidth, 1)) / CGFloat(max(photo.pixelHeight, 1)),
                                         contentMode: .fit)
                            .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 240)
                .clipShape(.rect(cornerRadius: 6))

                Text(photo.displayName).font(.title3.bold())
                    .textSelection(.enabled)

                switch placement {
                case .onQ2:      Label("On your Q2", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .nextSync:  Label("Copied at the next sync", systemImage: "arrow.down.circle").foregroundStyle(.secondary)
                case .notChosen: Label("Not chosen for your Q2", systemImage: "minus.circle").foregroundStyle(.secondary)
                case .cantSync, nil: EmptyView()
                }

                Divider()
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                    row("Taken", photo.created.formatted(date: .long, time: .shortened))
                    if let modified = photo.modified, modified > photo.created {
                        row("Edited", modified.formatted(date: .long, time: .shortened))
                    }
                    row("Size", "\(photo.pixelWidth) × \(photo.pixelHeight)")
                    row("Favourite", photo.isFavorite ? "Yes" : "No")
                    if photo.isHidden { row("Hidden", "Yes") }
                }
                .font(.callout)

                if !albums.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Albums").font(.headline)
                        ForEach(albums, id: \.self) { Text($0).font(.callout) }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled)
        }
    }
}

extension PhotoAsset {
    /// The original file name, or "Photo" when Photos doesn't know it.
    var displayName: String { originalFileName ?? "Photo" }

    /// Width × height, for sorting the Size column.
    var pixelCount: Int { pixelWidth * pixelHeight }
}

extension PhotoAlbumKind {
    /// The SF Symbol for an album of this kind, on the Photos tab and in
    /// the Albums browser.
    var symbolName: String {
        switch self {
        case .favorites: "heart"
        case .recentlyAdded: "clock"
        case .mediaType: "square.stack"
        case .hidden: "eye.slash"
        case .user: "rectangle.stack"
        }
    }
}
