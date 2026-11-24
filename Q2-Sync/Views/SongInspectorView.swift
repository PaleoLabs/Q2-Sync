//
//  SongInspectorView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The song inspector: everything about the song selected in the library
//  browser's song table. Artwork, title, artist and album; whether it can
//  be copied and whether it's on the Q2; then its tags, file and play
//  details, and Show in Finder. Read-only: nothing here changes the song.
//
//  HOW IT FITS
//  Shown by `LibraryCategoryView` as a SwiftUI inspector (a trailing
//  column), toggled with the toolbar's Info button or the song table's
//  right-click "Show Info". Artwork comes from `LibraryModel.artworkData`.
//

import AppKit
import SwiftUI

/// Details of one song, or a hint when none (or several) are selected.
struct SongInspectorView: View {

    /// The selected song, or `nil` for none or several.
    let track: Track?

    /// How many songs are selected (for the hint).
    let selectedCount: Int

    /// Its place on the Q2, if known.
    let placement: TrackPlacement?

    let library: LibraryModel

    /// The artwork, loaded when the song changes.
    @State private var artwork: NSImage?

    var body: some View {
        if let track {
            details(track)
                .task(id: track.id) {
                    artwork = nil
                    guard track.hasArtwork != false,
                          let data = await library.artworkData(for: track.id) else { return }
                    artwork = NSImage(data: data)
                }
        } else {
            ContentUnavailableView(selectedCount > 1 ? "\(selectedCount) Songs Selected" : "No Song Selected",
                                   systemImage: "info.circle",
                                   description: Text("Select one song to see its details."))
        }
    }

    // MARK: Details

    private func details(_ track: Track) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                artworkView
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).font(.title3.bold())
                        .textSelection(.enabled)
                    Text(track.displayArtist).foregroundStyle(.secondary)
                    Text(track.displayAlbum).foregroundStyle(.secondary)
                }

                statusRows(track)

                Divider()
                section("Song", rows: [
                    ("Album Artist", track.albumArtist),
                    ("Track", numberOf(track.trackNumber, nil)),
                    ("Disc", track.discCount > 1 ? numberOf(track.discNumber, track.discCount) : nil),
                    ("Year", track.year.map(String.init)),
                    ("Genre", track.genre),
                    ("Composer", track.composer),
                    ("Time", Duration.seconds(track.durationSeconds).formatted(.time(pattern: .minuteSecond))),
                    ("Compilation", track.isCompilation ? "Yes" : nil),
                ])

                Divider()
                section("File", rows: [
                    ("Name", track.fileURL?.lastPathComponent),
                    ("Kind", track.fileKind),
                    ("Size", track.fileSize > 0 ? Int64(track.fileSize).formatted(.byteCount(style: .file)) : nil),
                    ("Bit Rate", track.bitRate.map { "\($0) kbps" }),
                    ("Sample Rate", track.sampleRate.map { Self.sampleRateText($0) }),
                    ("Modified", track.modifiedDate.map(Self.dateText)),
                ])
                if let url = track.fileURL {
                    Text(url.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }

                Divider()
                section("Music", rows: [
                    ("Plays", track.playCount.map { $0.formatted() }),
                    ("Last Played", track.lastPlayed.map(Self.dateText)),
                    ("Added", track.dateAdded.map(Self.dateText)),
                ])
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Square artwork, or a placeholder note.
    private var artworkView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            if let artwork {
                Image(nsImage: artwork).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.secondary)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 240)
        .accessibilityLabel(artwork == nil ? "No artwork" : "Album artwork")
    }

    /// Can it be copied, and is it on the Q2.
    private func statusRows(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(track.isCopyable ? "Can sync to the Q2" : track.availability.explanation,
                  systemImage: track.availability.symbolName)
                .foregroundStyle(track.availability.tint)
                .fixedSize(horizontal: false, vertical: true)
            if track.availability == .fileMissing {
                Text(track.unavailableReason).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let placement {
                switch placement {
                case .onQ2:      Label("On your Q2", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .nextSync:  Label("Copied at the next sync", systemImage: "arrow.down.circle").foregroundStyle(.secondary)
                case .notChosen: Label("Not chosen for your Q2", systemImage: "minus.circle").foregroundStyle(.secondary)
                case .cantSync:  EmptyView()
                }
            }
        }
    }

    /// A titled group of label/value rows; rows with no value are left out.
    private func section(_ title: String, rows: [(String, String?)]) -> some View {
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

    // MARK: Formatting

    /// "3" or "3 of 12"; `nil` when unknown.
    private func numberOf(_ number: Int, _ count: Int?) -> String? {
        guard number > 0 else { return nil }
        if let count, count > 0 { return "\(number) of \(count)" }
        return "\(number)"
    }

    static func sampleRateText(_ hertz: Int) -> String {
        let kHz = Double(hertz) / 1000
        return kHz.formatted(.number.precision(.fractionLength(0...1))) + " kHz"
    }

    static func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
