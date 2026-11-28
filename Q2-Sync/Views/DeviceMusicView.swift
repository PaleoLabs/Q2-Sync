//
//  DeviceMusicView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The "Music" tab of the device page: "Sync music onto [Q2]", then
//  "Entire music library" or tick individual artists, albums, genres and
//  playlists, like Finder's iPod sync. A summary line shows how many songs and bytes will sync and
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
    /// `nil` while the library hasn't been read.
    let resolved: ResolvedSelection?

    /// Which section's checkboxes are showing.
    @State private var section: BrowseCategory = .artists

    /// Text typed in the filter field.
    @State private var filterText = ""

    /// Controls the skipped-songs popover.
    @State private var showingSkipped = false

    /// Starts syncs the same way the menu bar does.
    @Environment(AutoSyncController.self) private var autoSync

    /// The shown selection: unapplied edits, or what's saved.
    private var selection: SyncSelection {
        devices.shownSyncSettings?.music ?? connected.device.effectiveSelection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let snapshot = library.snapshot, let resolved {
                content(snapshot: snapshot)
                    // Like Finder: music off dims everything below the box.
                    .disabled(!selection.isEnabled)
                Divider()
                summaryBar(resolved)
            } else if selection.isEnabled {
                LibraryNotReadView(library: library)
            } else {
                ContentUnavailableView("Music Is Off", systemImage: "music.note",
                                       description: Text("Q2 Sync doesn't read your Apple Music library or put music on this Q2. Tick “Sync music” to choose music again."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Header

    /// "Sync music onto [Q2]", then entire library or selected items, like
    /// Finder, then a note.
    private var header: some View {
        SyncSectionHeader(
            title: "Sync music onto \(connected.device.name)",
            isEnabled: Binding(get: { selection.isEnabled },
                               set: { on in update { $0.isEnabled = on } }),
            choice: Binding(get: { selection.mode },
                            set: { mode in update { $0.mode = mode } }),
            options: [
                SyncChoiceOption(label: "Entire music library", value: .entireLibrary),
                SyncChoiceOption(label: "Selected artists, albums, genres, and playlists", value: .selectedItems),
            ]) {
            headerNote
        }
    }

    /// The note under the choices. Always laid out (invisible when there's
    /// nothing to say), so the list below doesn't jump when it goes.
    private var headerNote: some View {
        let note: SyncSectionNote? = if !selection.isEnabled {
            // Nothing happens until Apply and the review sheet's Remove Them.
            hasQ2SyncSongs
                ? SyncSectionNote(text: "Music is off. When you sync, the review lets you remove the songs and playlists Q2 Sync put on this card.",
                                  systemImage: "exclamationmark.triangle", color: .orange)
                : nil
        } else if selection.isEmpty {
            // The first step on a new Q2: nothing is chosen yet.
            hasQ2SyncSongs
                ? SyncSectionNote(text: "Nothing is chosen. Syncing now would remove the songs Q2 Sync put on this card.",
                                  systemImage: "exclamationmark.triangle", color: .orange)
                : SyncSectionNote(text: "Choose what to put on your Q2: your entire music library, or tick the artists, albums, genres and playlists you want. ⌘-click a box to tick or untick the whole list.",
                                  systemImage: "hand.point.down", color: .accentColor)
        } else {
            nil
        }
        return ZStack(alignment: .topLeading) {
            // Holds the space of the longest note so nothing moves.
            SyncSectionNote(text: "Choose what to put on your Q2: your entire music library, or tick the artists, albums, genres and playlists you want. ⌘-click a box to tick or untick the whole list.",
                            systemImage: "hand.point.down")
                .hidden()
            if let note { note }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Main content

    @ViewBuilder
    private func content(snapshot: LibrarySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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

            FilterTextField(text: $filterText, prompt: "Filter \(section.rawValue)", field: .musicTab)
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
            Text(pluralized(resolved.tracksToSync.count, "song"))
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
                    // Clears the ticks only; "Sync music" stays as it is.
                    update { $0 = SyncSelection(isEnabled: $0.isEnabled, mode: .selectedItems) }
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
        var audiobooks: [Audiobook]?
        var audiobookSettings: AudiobookSelection?
        var podcasts: [PodcastShow]?
        var podcastSettings: PodcastSelection?
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
