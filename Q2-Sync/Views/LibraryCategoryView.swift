//
//  LibraryCategoryView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  Browses one library category (Artists, Albums, Genres or Playlists):
//  a list of groups on the left, the selected group's tracks on the right.
//  It shows the library as it relates to the Q2: what can be copied at all
//  ("12 of 14 can sync") and, from the Mac-side record of the card, what's
//  on the Q2 and what the next sync adds, even while the Q2 is unplugged.
//  Read-only; choosing what to sync happens in `DeviceMusicView`.
//
//  HOW IT FITS
//  Shown by `RootView` when a Library row is selected in the sidebar.
//
//  SAFETY
//  Only reads the library snapshot. `RootView` reads the Music library the
//  first time the window shows; the toolbar's Refresh Music Library re-reads it.
//

import SwiftUI

/// The sidebar's library categories.
///
/// `CaseIterable` gives `allCases` to build the sidebar, and
/// `Identifiable` lets SwiftUI tell rows apart.
enum BrowseCategory: String, CaseIterable, Identifiable, Hashable {
    case artists = "Artists"
    case albums = "Albums"
    case genres = "Genres"
    case playlists = "Playlists"

    var id: String { rawValue }

    /// SF Symbol for the sidebar row (the same icons Music uses).
    var symbolName: String {
        switch self {
        case .artists:   return "music.microphone"
        case .albums:    return "square.stack"
        case .genres:    return "guitars"
        case .playlists: return "music.note.list"
        }
    }

    /// Column header for the group list, e.g. "Artist".
    var singularTitle: String {
        switch self {
        case .artists:   return "Artist"
        case .albums:    return "Album"
        case .genres:    return "Genre"
        case .playlists: return "Playlist"
        }
    }

    /// The groups for this category from a snapshot.
    func groups(in snapshot: LibrarySnapshot) -> [TrackGroup] {
        switch self {
        case .artists:   return snapshot.artistGroups
        case .albums:    return snapshot.albumGroups
        case .genres:    return snapshot.genreGroups
        case .playlists: return snapshot.playlistGroups
        }
    }
}

/// A two-pane browser for one category.
struct LibraryCategoryView: View {

    let library: LibraryModel
    let devices: DeviceMonitor
    let category: BrowseCategory

    /// The selected group's ID.
    @State private var groupID: String?

    /// Song marks, rebuilt when the library, Q2 record or selection changes.
    @State private var marks: LibraryMarks?

    /// Group counts for this category, by group ID (built with `marks`).
    @State private var groupMarks: [String: GroupMarks] = [:]

    /// Width of the group list. `HSplitView` halves the space when it first
    /// appears and ignores the ideal width, so the split is drawn by hand:
    /// it opens at the narrow width, drags like a divider, and is remembered.
    @AppStorage("libraryListWidth") private var listWidth: Double = Self.listWidthRange.lowerBound
    @State private var dragStartWidth: Double?

    /// Whether the song inspector is open (remembered across launches).
    @AppStorage("showSongInfo") private var showSongInfo = false

    /// The songs selected in the song table, for the inspector.
    @State private var selectedSongs: [Track] = []
    private static let listWidthRange: ClosedRange<Double> = 360...560

    /// What the marks depend on; a change rebuilds them.
    private struct MarksKey: Equatable {
        var loadCount: Int
        var category: BrowseCategory
        var record: CardContentsRecord?
        var selection: SyncSelection?
    }

    private var marksKey: MarksKey {
        let reference = devices.referenceContents
        return MarksKey(loadCount: library.loadCount, category: category,
                        record: reference?.record, selection: reference?.device.effectiveSelection)
    }

    var body: some View {
        Group {
            if let snapshot = library.snapshot {
                let groups = category.groups(in: snapshot)
                HStack(spacing: 0) {
                    // A table, not a list, so the marks and counts sit in
                    // aligned columns under headers. The marks travel inside
                    // each row value: `Table` only redraws a row when its
                    // value changes, not when other state the cell reads does.
                    let hasQ2 = marks?.hasQ2 ?? false
                    let rows = groups.map { GroupRow(group: $0, marks: groupMarks[$0.id], hasQ2: hasQ2) }
                    Table(rows, selection: $groupID) {
                        TableColumn(category.singularTitle) { row in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.group.title)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                if let subtitle = row.group.subtitle {
                                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .help(row.group.title)
                        }
                        TableColumn("On Q2") { row in
                            // Two fixed slots: can't-copy lock, then Q2 state.
                            HStack(spacing: 4) {
                                Group {
                                    if let counts = row.marks { GroupSyncIcon(marks: counts) }
                                }
                                .frame(width: 16)
                                Group {
                                    if let counts = row.marks, row.hasQ2 { GroupQ2Icon(marks: counts) }
                                }
                                .frame(width: 16)
                            }
                        }
                        .width(48)
                        TableColumn("Songs") { row in
                            Text((row.marks?.total ?? row.group.trackIDs.count).formatted())
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .width(44)
                    }
                    .frame(width: listWidth.clamped(to: Self.listWidthRange))

                    splitDivider

                    ZStack {
                        if let group = groups.first(where: { $0.id == groupID }) {
                            TrackTableView(tracks: snapshot.tracks(for: group.trackIDs), marks: marks,
                                           onSelect: { selectedSongs = $0 },
                                           onShowInfo: { showSongInfo = true })
                        } else {
                            ContentUnavailableView("Select an Item", systemImage: "music.note",
                                                   description: Text("Choose one on the left to see its songs."))
                        }
                    }
                    // Narrow enough that opening the inspector doesn't need a
                    // wider window.
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                LibraryNotReadView(library: library)
            }
        }
        .navigationTitle(category.rawValue)
        .navigationSubtitle(comparisonSubtitle)
        .inspector(isPresented: $showSongInfo) {
            let song = selectedSongs.count == 1 ? selectedSongs.first : nil
            SongInspectorView(track: song, selectedCount: selectedSongs.count,
                              placement: song.flatMap { marks?.placement(of: $0.id) },
                              library: library)
                .inspectorColumnWidth(min: 220, ideal: 260, max: 360)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $showSongInfo) {
                    Label("Song Info", systemImage: "info.circle")
                }
                .labelStyle(.titleAndIcon)
                .help("Show or hide details of the selected song")
            }
        }
        .onChange(of: category) { groupID = nil }
        .onChange(of: groupID) { selectedSongs = [] }
        .task(id: marksKey) { await rebuildMarks(for: marksKey) }
    }

    /// A thin line with a wider grab area that resizes the group list.
    private var splitDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = dragStartWidth ?? listWidth
                        dragStartWidth = start
                        listWidth = (start + drag.translation.width).clamped(to: Self.listWidthRange)
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
            .padding(.horizontal, -3)
    }

    /// "Compared with Shanling-Q2 · as of Nov 22, 10:14", or a hint.
    private var comparisonSubtitle: String {
        guard library.snapshot != nil else { return "" }
        guard let reference = devices.referenceContents else {
            return "Connect your Q2 to see what's on it"
        }
        let when = reference.record.checkedAt.formatted(date: .abbreviated, time: .shortened)
        return devices.connected?.device.volumeUUID == reference.device.volumeUUID
            ? "Compared with \(reference.device.name)"
            : "Compared with \(reference.device.name) · as of \(when)"
    }

    /// Rebuilds the marks off the main thread (resolving the selection
    /// walks the whole library), then publishes them.
    private func rebuildMarks(for key: MarksKey) async {
        guard let snapshot = library.snapshot else {
            marks = nil
            groupMarks = [:]
            return
        }
        let category = key.category
        let built = await Task.detached(priority: .userInitiated) {
            let marks = LibraryMarks(snapshot: snapshot, record: key.record, selection: key.selection)
            var counts: [String: GroupMarks] = [:]
            for group in category.groups(in: snapshot) {
                counts[group.id] = marks.marks(for: group.trackIDs)
            }
            return (marks, counts)
        }.value
        guard !Task.isCancelled else { return }
        marks = built.0
        groupMarks = built.1
    }
}

/// One row of the group table: the group plus its marks, so a change in
/// the marks changes the row value and the table redraws it.
struct GroupRow: Identifiable, Equatable {
    let group: TrackGroup
    let marks: GroupMarks?
    let hasQ2: Bool
    var id: String { group.id }
}

/// The lock slot: some (outline) or all (filled) songs can't be copied.
/// Blank when every song can be. Details in the tooltip.
struct GroupSyncIcon: View {

    let marks: GroupMarks

    var body: some View {
        if marks.syncable == 0 {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
                .help("None of these songs can be copied. Select it to see why for each song.")
        } else if marks.syncable < marks.total {
            Image(systemName: "lock")
                .foregroundStyle(.orange)
                .help("\(marks.syncable) of \(marks.total) songs can be copied. Select it to see why the others can't.")
        }
    }
}

/// The Q2 column: on the Q2 (check), partly (half circle), coming at the
/// next sync (blue arrow), or blank when not chosen. Quiet on purpose: the
/// usual case is a grey check.
struct GroupQ2Icon: View {

    let marks: GroupMarks

    private static let asOf = " (from Q2 Sync's record of the card when it was last connected)"

    var body: some View {
        if marks.syncable == 0 && marks.onQ2 == 0 {
            EmptyView()
        } else if marks.onQ2 >= marks.syncable {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
                .help("On your Q2" + Self.asOf + ".")
        } else if marks.onQ2 > 0 {
            let next = marks.nextSync > 0 ? "; \(marks.nextSync) more at the next sync" : ""
            Image(systemName: "circle.lefthalf.filled")
                .foregroundStyle(.secondary)
                .help("\(marks.onQ2) of \(marks.syncable) on your Q2\(next)" + Self.asOf + ".")
        } else if marks.nextSync > 0 {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
                .help("\(marks.nextSync) chosen for your Q2 but not copied yet. They go over at the next sync.")
        }
    }
}

// MARK: - Playlist groups

extension LibrarySnapshot {

    /// Playlists presented as `TrackGroup`s, so the browser can treat them
    /// like artists or albums. Folders are left out (they hold no tracks).
    var playlistGroups: [TrackGroup] {
        playlists
            .filter { $0.kind != .folder }
            .map { TrackGroup(id: "playlist:\($0.id)", title: $0.name,
                              subtitle: $0.kind == .smart ? "Smart Playlist" : nil,
                              trackIDs: $0.trackIDs) }
            .sorted { SortKey.compare($0.title, $1.title) }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
