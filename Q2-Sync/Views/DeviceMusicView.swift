//
//  DeviceMusicView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The "Music" tab of the device page: choose "Entire music library" or
//  tick individual artists, albums, genres and playlists, like Finder's
//  iPod sync. A summary line shows how many songs and bytes will sync and
//  how many will be skipped (cloud-only, protected, missing).
//
//  HOW IT FITS
//  Reads the library snapshot from `LibraryModel`. Changes are edits
//  through `DeviceMonitor.editSyncSettings`, saved only on Apply (see
//  `DeviceSyncBar`). `DeviceView` resolves the shown selection once and
//  passes it in, since the capacity bar below the tabs needs it too.
//

import SwiftUI

/// Choose what to sync to the Q2.
struct DeviceMusicView: View {

    let connected: ConnectedDevice
    let devices: DeviceMonitor
    let library: LibraryModel

    /// The shown selection, resolved against the library by `DeviceView`.
    let resolved: ResolvedSelection

    /// Which section's checkboxes are showing.
    @State private var section: BrowseCategory = .artists

    /// Text typed in the filter field.
    @State private var filterText = ""

    /// Whether the cursor is in the filter field.
    @FocusState private var isFilterFocused: Bool

    /// Controls the skipped-songs popover.
    @State private var showingSkipped = false

    /// Starts syncs the same way the menu bar does.
    @Environment(AutoSyncController.self) private var autoSync

    /// The shown selection: unapplied edits, or what's saved.
    private var selection: SyncSelection {
        devices.shownSyncSettings?.music ?? connected.device.effectiveSelection
    }

    var body: some View {
        if let snapshot = library.snapshot {
            content(snapshot: snapshot)
        } else {
            LibraryNotReadView(library: library)
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private func content(snapshot: LibrarySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // The first step on a new Q2: nothing is chosen yet.
            // Always laid out, and just made invisible once something is
            // ticked, so the list below doesn't jump up when it goes.
            do {
                Label(hasQ2SyncSongs
                      ? "Nothing is chosen. Syncing now would remove the songs Q2 Sync put on this card."
                      : "Choose what to put on your Q2: your entire music library, or tick the artists, albums, genres and playlists you want. ⌘-click a box to tick or untick the whole list.",
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
                    // Fill the space so the summary and Sync bars sit at the bottom.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
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

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter", text: $filterText, prompt: Text("Filter \(section.rawValue)"))
                    .textFieldStyle(.plain)
                    .focused($isFilterFocused)
                if !filterText.isEmpty {
                    Button {
                        filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear the filter")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            .frame(maxWidth: 220)
        }
        .onChange(of: section) { filterText = "" }
        // Edit › Find (⌘F) puts the cursor in the filter.
        .onAppear { autoSync.navigation.filterAppeared(.musicTab) }
        .onDisappear { autoSync.navigation.filterDisappeared(.musicTab) }
        .onChange(of: autoSync.navigation.findRequests) {
            if autoSync.navigation.filterField == .musicTab { isFilterFocused = true }
        }
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
            ChecklistTableView(rows: rows, ticked: ticked) { rowIDs, isOn in
                setTicked(rowIDs, isOn, in: section)
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

    /// Ticks or unticks rows and saves the selection once.
    ///
    /// - Parameters:
    ///   - rowIDs: The rows' group IDs (`"playlist:<id>"` for playlists).
    ///   - isOn: The new state.
    ///   - category: The section the rows are in.
    private func setTicked(_ rowIDs: [String], _ isOn: Bool, in category: BrowseCategory) {
        update { selection in
            switch category {
            case .artists:   selection.artistIDs.toggle(rowIDs, on: isOn)
            case .albums:    selection.albumIDs.toggle(rowIDs, on: isOn)
            case .genres:    selection.genreIDs.toggle(rowIDs, on: isOn)
            case .playlists:
                selection.playlistIDs.toggle(rowIDs.map { String($0.dropFirst("playlist:".count)) }, on: isOn)
            }
        }
    }

    /// `true` if the card holds songs Q2 Sync put there. Then an empty
    /// selection is a real choice (remove them all); otherwise there's
    /// nothing to sync yet.
    private var hasQ2SyncSongs: Bool { devices.cardHasQ2SyncSongs }

    /// Changes the shown selection. Saved only on Apply.
    ///
    /// - Parameter change: A closure that edits a copy of the selection.
    ///   `inout` lets the closure modify the copy in place.
    private func update(_ change: (inout SyncSelection) -> Void) {
        devices.editSyncSettings { change(&$0.music) }
    }

    // MARK: - Summary bar

    /// "1,234 songs · 8.2 GB · 32 skipped" plus Deselect All. The Sync,
    /// Revert and Apply buttons are in `DeviceSyncBar`, below the tabs.
    private func summaryBar(_ resolved: ResolvedSelection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
            Text("\(resolved.tracksToSync.count.formatted()) songs")
                .fontWeight(.medium)
            // Total playing time, e.g. "3d 4h" or "2h 35m".
            if resolved.totalDurationSeconds >= 60 {
                Text(Duration.seconds(resolved.totalDurationSeconds)
                        .formatted(.units(allowed: [.days, .hours, .minutes], width: .narrow, maximumUnitCount: 2)))
                    .foregroundStyle(.secondary)
            }
            Text(Int64(resolved.totalBytes).formatted(ByteCountFormatStyle(style: .file)))
                .foregroundStyle(.secondary)
            if !resolved.playlists.isEmpty {
                Text(pluralized(resolved.playlists.count, "playlist")).foregroundStyle(.secondary)
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
                .help("Untick everything on every tab. To tick or untick only this tab, ⌘-click a checkbox.")
            }
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
    /// Inserts or removes elements depending on `on`. Makes checkbox
    /// code read naturally: `ids.toggle(clicked, on: isChecked)`.
    mutating func toggle(_ elements: [Element], on: Bool) {
        if on { formUnion(elements) } else { subtract(elements) }
    }
}

/// The device page's last resolved selection and capacity estimate. Working
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
