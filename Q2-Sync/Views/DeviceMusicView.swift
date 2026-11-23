//
//  DeviceMusicView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The "Music" tab of the device page: choose "Entire music library" or
//  tick individual artists, albums, genres and playlists, like Finder's
//  iPod sync. A summary bar shows how many songs and bytes will sync and
//  how many will be skipped (cloud-only, protected, missing).
//
//  HOW IT FITS
//  Reads the library snapshot from `LibraryModel`, reads and saves the
//  selection through `DeviceMonitor` (stored per device), and uses
//  `SelectionResolver` (Core) for the summary. The summary bar holds the
//  Sync button, and `CapacityBarView` sits above it.
//

import SwiftUI

/// Choose what to sync to the Q2.
struct DeviceMusicView: View {

    let connected: ConnectedDevice
    let devices: DeviceMonitor
    let library: LibraryModel

    /// Which section's checkboxes are showing.
    @State private var section: BrowseCategory = .artists

    /// Text typed in the filter field.
    @State private var filterText = ""

    /// Controls the skipped-songs popover.
    @State private var showingSkipped = false

    /// The last resolved selection and space numbers (see `MusicTabCache`).
    @State private var cache = MusicTabCache()

    /// Runs syncs (from the environment, set up in `Q2SyncApp`).
    @Environment(SyncCoordinator.self) private var sync

    /// Starts syncs the same way the menu bar does.
    @Environment(AutoSyncController.self) private var autoSync

    /// The saved selection for this device.
    private var selection: SyncSelection { connected.device.effectiveSelection }

    var body: some View {
        if let snapshot = library.snapshot {
            content(snapshot: snapshot)
        } else {
            VStack(spacing: 0) {
                LibraryNotReadView(library: library)
                Divider()
                // Current card usage, before any selection is known.
                CapacityBarView(estimate: capacity(for: nil))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
        }
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

    // MARK: - Main content

    @ViewBuilder
    private func content(snapshot: LibrarySnapshot) -> some View {
        // Redone only when the selection, library or card changed, not on
        // every redraw (typing in the filter, switching sections…).
        let key = MusicTabCache.Key(
            selection: selection, libraryLoad: library.loadCount, trackCount: snapshot.tracks.count,
            manifestSavedAt: devices.cardManifest?.updatedAt, manifestCount: devices.cardManifest?.entries.count,
            totalBytes: connected.volume.totalCapacity ?? 0, freeBytes: connected.volume.availableCapacity ?? 0,
            cardReadable: connected.accessURL != nil)
        let (resolved, estimate) = cache.values(for: key) {
            let resolved = SelectionResolver.resolve(selection, in: snapshot)
            return (resolved, capacity(for: resolved))
        }

        VStack(alignment: .leading, spacing: 0) {
            // The first step on a new Q2: nothing is chosen yet.
            // Always laid out, and just made invisible once something is
            // ticked, so the list below doesn't jump up when it goes.
            do {
                Label(hasQ2SyncSongs
                      ? "Nothing is chosen. Syncing now would remove the songs Q2 Sync put on this card."
                      : "Choose what to put on your Q2: your entire music library, or tick the artists, albums, genres and playlists you want.",
                      systemImage: hasQ2SyncSongs ? "exclamationmark.triangle" : "hand.point.down")
                    .foregroundStyle(hasQ2SyncSongs ? .orange : .accentColor)
                    // Wraps to the width it's given. Not `fixedSize(vertical:)`:
                    // measured narrow, that made the line ask for a huge
                    // minimum height, and right after a card was set up the
                    // page overflowed the window (header pushed off the top,
                    // sidebar blank) until the first click (#43).
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .opacity(selection.isEmpty ? 1 : 0)
                    .accessibilityHidden(!selection.isEmpty)
            }

            // "Entire library" vs "Selected items", like Finder.
            Picker("Sync", selection: Binding(
                get: { selection.mode },
                set: { mode in update { $0.mode = mode } })) {
                Text("Entire music library").tag(SyncSelection.Mode.entireLibrary)
                Text("Selected artists, albums, genres, and playlists").tag(SyncSelection.Mode.selectedItems)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if selection.mode == .selectedItems {
                sectionPicker
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                checklist(snapshot: snapshot)
            } else {
                ContentUnavailableView("Your Entire Library",
                                       systemImage: "music.note.list",
                                       description: Text("Every song and playlist that can be copied will be synced."))
                    // Fill the space so the capacity and Sync bars sit at the bottom.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            // Finder-style bar: what the card holds and what this sync adds.
            CapacityBarView(estimate: estimate)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            summaryBar(resolved)
        }
    }

    // MARK: - Section picker and filter

    /// Segmented control for the four sections, plus a filter field.
    private var sectionPicker: some View {
        HStack {
            Picker("Section", selection: $section) {
                ForEach(BrowseCategory.allCases) { category in
                    Text(sectionTitle(category)).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()

            TextField("Filter", text: $filterText, prompt: Text("Filter \(section.rawValue)"))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
        }
        .onChange(of: section) { filterText = "" }
    }

    /// e.g. "Artists" or "Artists (3)" when some are ticked.
    private func sectionTitle(_ category: BrowseCategory) -> String {
        let count = tickedIDs(for: category).count
        return count > 0 ? "\(category.rawValue) (\(count))" : category.rawValue
    }

    // MARK: - Checklist

    /// The checkbox list for the current section.
    @ViewBuilder
    private func checklist(snapshot: LibrarySnapshot) -> some View {
        let rows = filteredRows(snapshot: snapshot)
        // Worked out once per redraw, not once per checkbox.
        let ticked = tickedIDs(for: section)
        if rows.isEmpty {
            ContentUnavailableView.search(text: filterText)
        } else {
            // AppKit, not a SwiftUI `List`: plain reused rows however long
            // the list (see `ChecklistTableView`).
            ChecklistTableView(rows: rows, ticked: ticked) { rowID, isOn in
                setTicked(rowID, isOn, in: section)
            }
        }
    }

    /// The current section's rows, filtered by the filter text.
    ///
    /// For playlists the group ID is `"playlist:<id>"`; we keep that
    /// format in the list and strip the prefix when saving.
    private func filteredRows(snapshot: LibrarySnapshot) -> [TrackGroup] {
        let rows = section.groups(in: snapshot).map { group -> TrackGroup in
            guard section == .playlists else { return group }
            // Show the folder a playlist lives in as its subtitle.
            let playlistID = String(group.id.dropFirst("playlist:".count))
            let folderName = snapshot.playlists.first { $0.id == playlistID }?.parentID
                .flatMap { parent in snapshot.playlists.first { $0.id == parent }?.name }
            let subtitle = [group.subtitle, folderName.map { "in \($0)" }]
                .compactMap { $0 }.joined(separator: " · ")
            return TrackGroup(id: group.id, title: group.title,
                              subtitle: subtitle.isEmpty ? nil : subtitle, trackIDs: group.trackIDs)
        }
        let query = filterText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return rows }
        return rows.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    /// The saved IDs for a section, in the form the list rows use.
    private func tickedIDs(for category: BrowseCategory) -> Set<String> {
        switch category {
        case .artists:   return selection.artistIDs
        case .albums:    return selection.albumIDs
        case .genres:    return selection.genreIDs
        case .playlists: return Set(selection.playlistIDs.map { "playlist:\($0)" })
        }
    }

    /// Ticks or unticks a row and saves the selection.
    ///
    /// - Parameters:
    ///   - rowID: The row's group ID (`"playlist:<id>"` for playlists).
    ///   - isOn: The new state.
    ///   - category: The section the row is in.
    private func setTicked(_ rowID: String, _ isOn: Bool, in category: BrowseCategory) {
        update { selection in
            switch category {
            case .artists:   selection.artistIDs.toggle(rowID, on: isOn)
            case .albums:    selection.albumIDs.toggle(rowID, on: isOn)
            case .genres:    selection.genreIDs.toggle(rowID, on: isOn)
            case .playlists:
                selection.playlistIDs.toggle(String(rowID.dropFirst("playlist:".count)), on: isOn)
            }
        }
    }

    /// `true` if the card holds songs Q2 Sync put there. Then an empty
    /// selection is a real choice (remove them all); otherwise there's
    /// nothing to sync yet.
    private var hasQ2SyncSongs: Bool {
        !(devices.cardManifest?.entries.isEmpty ?? true)
    }

    /// Applies a change to the selection and saves it.
    ///
    /// - Parameter change: A closure that edits a copy of the selection.
    ///   `inout` lets the closure modify the copy in place.
    private func update(_ change: (inout SyncSelection) -> Void) {
        var copy = selection
        change(&copy)
        devices.setSelection(copy)
    }

    // MARK: - Summary bar

    /// "1,234 songs · 8.2 GB · 32 skipped" plus Deselect All.
    private func summaryBar(_ resolved: ResolvedSelection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
            Text("\(resolved.tracksToSync.count.formatted()) songs")
                .fontWeight(.medium)
            Text(Int64(resolved.totalBytes).formatted(ByteCountFormatStyle(style: .file)))
                .foregroundStyle(.secondary)
            if !resolved.playlists.isEmpty {
                Text("\(resolved.playlists.count) playlists").foregroundStyle(.secondary)
            }

            if !resolved.skippedTracks.isEmpty {
                Button {
                    showingSkipped = true
                } label: {
                    Label("\(resolved.skippedTracks.count.formatted()) can't be synced",
                          systemImage: "exclamationmark.circle")
                }
                .buttonStyle(.link)
                .popover(isPresented: $showingSkipped, arrowEdge: .top) {
                    SkippedSummaryView(resolved: resolved)
                }
            }

            Spacer()

            if selection.mode == .selectedItems && selection.tickedItemCount > 0 {
                Button("Deselect All") {
                    update { $0 = SyncSelection(mode: .selectedItems) }
                }
            }

            Button {
                Task { await autoSync.startSync(automatic: false) }
            } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .disabled(sync.phase != .idle || connected.accessURL == nil || (selection.isEmpty && !hasQ2SyncSongs))
            .help(selection.isEmpty && !hasQ2SyncSongs
                  ? "Choose some music first"
                  : "Review the changes, then copy them to the Q2")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// Popover explaining which selected songs can't be synced, and why.
struct SkippedSummaryView: View {

    let resolved: ResolvedSelection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Some selected songs can't be synced")
                .font(.headline)
            ForEach(TrackAvailability.allCases, id: \.self) { kind in
                if let count = resolved.skippedCounts[kind] {
                    Label("\(kind.reportDescription): \(count.formatted())", systemImage: kind.symbolName)
                        .foregroundStyle(kind.tint)
                }
            }
            Text("Q2 Sync never downloads songs from iCloud. To include cloud songs, download them in Music first.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(width: 320)
    }
}

extension Set {
    /// Inserts or removes an element depending on `on`. Makes checkbox
    /// code read naturally: `ids.toggle(id, on: isChecked)`.
    mutating func toggle(_ element: Element, on: Bool) {
        if on { insert(element) } else { remove(element) }
    }
}

/// The Music tab's last resolved selection and capacity estimate. Working
/// them out goes through every song in the library and on the card, so
/// they're kept until something they depend on changes. A class held in
/// `@State`: updating it doesn't redraw the view.
final class MusicTabCache {

    /// Everything the values depend on.
    struct Key: Equatable {
        var selection: SyncSelection
        var libraryLoad: Int
        var trackCount: Int
        var manifestSavedAt: Date?
        var manifestCount: Int?
        var totalBytes: Int64
        var freeBytes: Int64
        var cardReadable: Bool
    }

    private var key: Key?
    private var stored: (ResolvedSelection, CapacityEstimate)?

    /// The kept values if `key` matches, else `make()`'s (then kept).
    func values(for key: Key, _ make: () -> (ResolvedSelection, CapacityEstimate))
        -> (ResolvedSelection, CapacityEstimate) {
        if key == self.key, let stored { return stored }
        let made = make()
        self.key = key
        stored = made
        return made
    }
}
