//
//  TrackTableView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  A sortable, Finder-style table of tracks showing tags, duration,
//  availability and the source file path on your Mac (handy for checking
//  what ITLibrary reports).
//
//  HOW IT FITS
//  Shown on the right of `LibraryCategoryView`.
//

import SwiftUI

/// A table of tracks.
struct TrackTableView: View {

    /// The tracks to show, in their natural (album/playlist) order.
    let tracks: [Track]

    /// Q2 marks for the songs, or `nil` while they're being worked out.
    var marks: LibraryMarks? = nil

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

    /// Rows in the order the user asked for.
    private var rows: [Row] {
        let rows = tracks.enumerated().map { Row(position: $0.offset, track: $0.element,
                                                 placement: marks?.placement(of: $0.element.id)) }
        return sortOrder.isEmpty ? rows : rows.sorted(using: sortOrder)
    }

    var body: some View {
        Table(rows, sortOrder: $sortOrder) {
            TableColumn("#") { row in let track = row.track
                Text(track.trackNumber > 0 ? "\(track.trackNumber)" : "")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(28)

            TableColumn("Title", value: \.track.title)

            TableColumn("Artist", value: \.track.displayArtist)

            TableColumn("Album", value: \.track.displayAlbum)

            TableColumn("Time", value: \.track.durationSeconds) { row in let track = row.track
                Text(Duration.seconds(track.durationSeconds)
                        .formatted(.time(pattern: .minuteSecond)))
                    .monospacedDigit()
            }
            .width(50)

            TableColumn("Status") { row in let track = row.track
                Label(track.availability.shortName, systemImage: track.availability.symbolName)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(track.availability.tint)
                    .help(track.availability.explanation)
            }
            .width(44)

            TableColumn("Q2") { row in
                if let placement = row.placement {
                    PlacementLabel(placement: placement)
                        .labelStyle(.iconOnly)
                }
            }
            .width(32)

            TableColumn("File") { row in let track = row.track
                Text(track.fileURL?.path ?? "—")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(track.fileURL?.path ?? "No local file")
                    .textSelection(.enabled)
            }
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
