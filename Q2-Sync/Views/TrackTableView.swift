//
//  TrackTableView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  A sortable, Finder-style table of tracks showing tags, duration and
//  availability. The source file path on your Mac is in each title's
//  tooltip, the right-click menu (Show in Finder, Copy Path) and an
//  optional File column, hidden by default (right-click the header).
//
//  HOW IT FITS
//  Shown on the right of `LibraryCategoryView`.
//

import AppKit
import SwiftUI

/// A table of tracks.
struct TrackTableView: View {

    /// The tracks to show, in their natural (album/playlist) order.
    let tracks: [Track]

    /// Q2 marks for the songs, or `nil` while they're being worked out.
    var marks: LibraryMarks? = nil

    /// Called with the selected songs whenever the selection changes (for
    /// the song inspector).
    var onSelect: ([Track]) -> Void = { _ in }

    /// Called by the right-click menu's "Show Info".
    var onShowInfo: (() -> Void)? = nil

    /// One table row: the track plus its Q2 placement. The placement is in
    /// the row value so the table redraws when it changes (a `Table` only
    /// redraws rows whose value changed). `position` keeps rows distinct
    /// when a playlist lists the same song twice.
    struct Row: Identifiable, Equatable {
        let position: Int
        let track: Track
        let placement: TrackPlacement?
        var id: Int { position }
    }

    /// The table's current sort, changed by clicking column headers.
    /// Empty means "keep the natural order".
    @State private var sortOrder: [KeyPathComparator<Row>] = []

    /// Selected rows, so the right-click menu knows what it acts on.
    @State private var selection: Set<Row.ID> = []

    /// Which columns are shown, in what order and width (the header's
    /// right-click menu). Kept across launches as JSON in `columnsData`.
    @State private var columns = TableColumnCustomization<Row>()
    @AppStorage("trackTableColumns") private var columnsData = Data()

    /// Rows in the order the user asked for.
    private var rows: [Row] {
        let rows = tracks.enumerated().map { Row(position: $0.offset, track: $0.element,
                                                 placement: marks?.placement(of: $0.element.id)) }
        return sortOrder.isEmpty ? rows : rows.sorted(using: sortOrder)
    }

    var body: some View {
        let rows = rows
        Table(rows, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columns) {
            TableColumn("#") { row in let track = row.track
                Text(track.trackNumber > 0 ? "\(track.trackNumber)" : "")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(28)
            .customizationID("number")

            TableColumn("Title", value: \.track.title) { row in
                Text(row.track.title)
                    .help(row.track.fileURL?.path ?? "No file on this Mac")
            }
            .customizationID("title")

            TableColumn("Artist", value: \.track.displayArtist)
                .customizationID("artist")

            TableColumn("Album", value: \.track.displayAlbum)
                .customizationID("album")

            TableColumn("Time", value: \.track.durationSeconds) { row in let track = row.track
                Text(Duration.seconds(track.durationSeconds)
                        .formatted(.time(pattern: .minuteSecond)))
                    .monospacedDigit()
            }
            .width(50)
            .customizationID("time")

            TableColumn("Status") { row in let track = row.track
                Label(track.availability.shortName, systemImage: track.availability.symbolName)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(track.availability.tint)
                    .help(track.availability.explanation)
            }
            .width(44)
            .customizationID("status")

            TableColumn("Q2") { row in
                if let placement = row.placement {
                    PlacementLabel(placement: placement)
                        .labelStyle(.iconOnly)
                }
            }
            .width(32)
            .customizationID("q2")

            // Too long to read in a column, so off unless asked for.
            TableColumn("File") { row in let track = row.track
                Text(track.fileURL?.path ?? "—")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(track.fileURL?.path ?? "No file on this Mac")
                    .textSelection(.enabled)
            }
            .customizationID("file")
            .defaultVisibility(.hidden)
        }
        .contextMenu(forSelectionType: Row.ID.self) { ids in
            let urls = rows.filter { ids.contains($0.id) }.compactMap(\.track.fileURL)
            if let onShowInfo {
                Button("Show Info") {
                    selection = ids // Right-clicking an unselected row means that row.
                    onShowInfo()
                }
                    .disabled(ids.isEmpty)
                Divider()
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
            .disabled(urls.isEmpty)
            Button(urls.count > 1 ? "Copy Paths" : "Copy Path") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            }
            .disabled(urls.isEmpty)
        }
        .onChange(of: tracks.map(\.id)) { selection = [] }
        .onChange(of: selection) {
            onSelect(rows.filter { selection.contains($0.id) }.map(\.track))
        }
        .onAppear {
            if let saved = try? JSONDecoder().decode(TableColumnCustomization<Row>.self, from: columnsData) {
                columns = saved
            }
        }
        .onChange(of: columns) {
            if let data = try? JSONEncoder().encode(columns) { columnsData = data }
        }
    }
}

/// A song's place on the Q2, for the table's Q2 column.
struct PlacementLabel: View {

    let placement: TrackPlacement

    var body: some View {
        switch placement {
        case .onQ2:
            Label("On Q2", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("On your Q2, as of Q2 Sync's record of the card.")
        case .nextSync:
            Label("Next sync", systemImage: "arrow.down.circle")
                .foregroundStyle(.blue)
                .help("Chosen for your Q2 but not copied yet. It goes over at the next sync.")
        case .notChosen:
            Text("—")
                .foregroundStyle(.tertiary)
                .help("Not chosen for your Q2. Choose it on the Q2's Music tab.")
        case .cantSync:
            EmptyView()
        }
    }
}

#Preview {
    TrackTableView(tracks: [])
}
