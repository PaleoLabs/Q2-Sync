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

extension FocusedValues {
    /// `true` when the frontmost window shows a view with a Song Info panel
    /// (read by `SongInfoCommands` to enable its menu item).
    @Entry var offersSongInfo: Bool?
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

    /// What the marks depend on; a change rebuilds them. Compared on every
    /// redraw, so it holds the card record's identity (which card, when it
    /// was read, how many songs), not its ~10,000 song IDs: comparing those
    /// on the main thread each redraw made scrolling big lists stutter.
    private struct MarksKey: Equatable {
        var loadCount: Int
        var category: BrowseCategory
        var recordCard: String?
        var recordCheckedAt: Date?
        var recordSongCount: Int?
        var selection: SyncSelection?
    }

    private var marksKey: MarksKey {
        let reference = devices.referenceContents
        return MarksKey(loadCount: library.loadCount, category: category,
                        recordCard: reference?.record.volumeUUID, recordCheckedAt: reference?.record.checkedAt,
                        recordSongCount: reference?.record.trackIDs.count,
                        selection: reference?.device.effectiveSelection)
    }

    var body: some View {
        Group {
            if let snapshot = library.snapshot {
                let groups = category.groups(in: snapshot)
                HStack(spacing: 0) {
                    // An AppKit table (see `GroupTableView`), so the marks and
                    // counts sit in aligned columns and long lists scroll
                    // without building a SwiftUI view per cell.
                    let hasQ2 = marks?.hasQ2 ?? false
                    let rows = groups.map { GroupRow(group: $0, marks: groupMarks[$0.id], hasQ2: hasQ2) }
                    GroupTableView(rows: rows, title: category.singularTitle, selection: $groupID)
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
        // Enables View › Show Song Info while this view is showing.
        .focusedSceneValue(\.offersSongInfo, true)
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
                .help("Show or hide details of the selected song (⌘I)")
            }
        }
        .onChange(of: category) { groupID = nil }
        .onChange(of: groupID) { selectedSongs = [] }
        .task(id: marksKey) {
            let reference = devices.referenceContents
            await rebuildMarks(category: category, record: reference?.record,
                               selection: reference?.device.effectiveSelection)
        }
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
    private func rebuildMarks(category: BrowseCategory, record: CardContentsRecord?,
                              selection: SyncSelection?) async {
        guard let snapshot = library.snapshot else {
            marks = nil
            groupMarks = [:]
            return
        }
        let built = await Task.detached(priority: .userInitiated) {
            let marks = LibraryMarks(snapshot: snapshot, record: record, selection: selection)
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

// MARK: - Playlist groups

extension LibrarySnapshot {

    /// Playlists presented as `TrackGroup`s, so the browser can treat them
    /// like artists or albums. Folders are left out (they hold no tracks).
    var playlistGroups: [TrackGroup] {
        memoized("playlistGroups") {
            playlists
                .filter { $0.kind != .folder }
                .map { TrackGroup(id: "playlist:\($0.id)", title: $0.name,
                                  subtitle: $0.kind == .smart ? "Smart Playlist" : nil,
                                  trackIDs: $0.trackIDs) }
                .sorted { SortKey.compare($0.title, $1.title) }
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
