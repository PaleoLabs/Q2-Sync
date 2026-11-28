//
//  EpisodeInspectorView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The Episode Info panel: everything about the episode selected in the
//  Episodes browser. Title and show; whether it can be copied and whether
//  it's on the Q2; its date, played state, type and size; then its file
//  and Show in Finder. Read-only: nothing here changes the Podcasts app.
//
//  HOW IT FITS
//  Shown by `PodcastBrowserView` as a SwiftUI inspector, toggled with the
//  toolbar's Episode Info button, View › Show Episode Info (⌘I), a
//  double-click or the table's right-click "Show Info". Laid out like
//  `BookInspectorView`.
//

import AppKit
import SwiftUI

/// Details of one episode, or a hint when none (or several) are selected.
struct EpisodeInspectorView: View {

    /// The selected episode, or `nil` for none or several.
    let episode: PodcastEpisode?

    /// How many episodes are selected (for the hint).
    let selectedCount: Int

    /// Its place with the Q2, if known.
    let placement: TrackPlacement?

    var body: some View {
        if let episode {
            details(episode)
        } else {
            ContentUnavailableView(selectedCount > 1 ? "\(selectedCount) Episodes Selected" : "No Episode Selected",
                                   systemImage: "info.circle",
                                   description: Text("Select one episode to see its details."))
        }
    }

    private func details(_ episode: PodcastEpisode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.title).font(.title3.bold())
                        .textSelection(.enabled)
                    Text(episode.showTitle).foregroundStyle(.secondary)
                }

                statusRows(episode)

                Divider()
                rows("Episode", [
                    ("Show", episode.showTitle),
                    ("Published", episode.published?.formatted(date: .long, time: .omitted)),
                    ("Played", episode.playState == .unplayed ? "Not yet" : episode.playState.label),
                    ("Type", episode.kind == .video ? "Video" : "Audio (\(episode.fileExtension.uppercased()))"),
                    ("Size", Int64(episode.fileSize).formatted(.byteCount(style: .file))),
                ])

                Divider()
                fileSection(episode)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Can it be copied, and is it on the Q2.
    private func statusRows(_ episode: PodcastEpisode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reason = episode.unsyncableReason {
                Label(reason, systemImage: episode.isProtected ? "lock.fill" : "film")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Can sync to the Q2", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
            switch placement {
            case .onQ2:      Label("On your Q2", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .nextSync:  Label("Copied at the next sync", systemImage: "arrow.down.circle").foregroundStyle(.secondary)
            case .notChosen: Label("Not chosen for your Q2", systemImage: "minus.circle").foregroundStyle(.secondary)
            case .cantSync, nil: EmptyView()
            }
            if placement == .onQ2 {
                Text("Playing it on the Q2 doesn't mark it played on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The downloaded file and where it is.
    private func fileSection(_ episode: PodcastEpisode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("File").font(.headline)
            Text(episode.fileURL.lastPathComponent)
                .font(.callout)
                .textSelection(.enabled)
            Text(episode.fileURL.deletingLastPathComponent().path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([episode.fileURL])
            }
        }
    }

    /// A titled group of label/value rows; rows with no value are left out.
    private func rows(_ title: String, _ rows: [(String, String?)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                ForEach(rows.filter { $0.1 != nil }, id: \.0) { label, value in
                    GridRow {
                        Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        Text(value ?? "").textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.callout)
        }
    }
}
