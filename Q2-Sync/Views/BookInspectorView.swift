//
//  BookInspectorView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The Book Info panel: everything about the book selected in the Books
//  browser. Title and author; whether it can be copied and whether it's on
//  the Q2; its length and size; then each of its files (parts), and Show
//  in Finder. Read-only: nothing here changes the book.
//
//  HOW IT FITS
//  Shown by `AudiobookBrowserView` as a SwiftUI inspector, toggled with the
//  toolbar's Book Info button, View › Show Book Info (⌘I), a double-click
//  or the table's right-click "Show Info". Laid out like
//  `SongInspectorView`. No cover yet: `Audiobook` doesn't read covers.
//

import AppKit
import SwiftUI

/// Details of one book, or a hint when none (or several) are selected.
struct BookInspectorView: View {

    /// The selected book, or `nil` for none or several.
    let book: Audiobook?

    /// How many books are selected (for the hint).
    let selectedCount: Int

    /// Its place with the Q2, if known.
    let placement: TrackPlacement?

    var body: some View {
        if let book {
            details(book)
        } else {
            ContentUnavailableView(selectedCount > 1 ? "\(selectedCount) Books Selected" : "No Book Selected",
                                   systemImage: "info.circle",
                                   description: Text("Select one book to see its details."))
        }
    }

    private func details(_ book: Audiobook) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title).font(.title3.bold())
                        .textSelection(.enabled)
                    if let author = book.author {
                        Text(author).foregroundStyle(.secondary)
                    }
                }

                statusRows(book)

                Divider()
                rows("Book", [
                    ("Author", book.author),
                    ("Length", book.durationSeconds > 0
                        ? Duration.seconds(book.durationSeconds).formatted(.time(pattern: .hourMinuteSecond))
                        : nil),
                    ("Size", Int64(book.totalSize).formatted(.byteCount(style: .file))),
                    ("Files", book.parts.count.formatted()),
                ])

                Divider()
                partsSection(book)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Can it be copied, and is it on the Q2.
    private func statusRows(_ book: Audiobook) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(book.availability == .available ? "Can sync to the Q2" : book.availability.audiobookExplanation,
                  systemImage: book.availability.symbolName)
                .foregroundStyle(book.availability.tint)
                .fixedSize(horizontal: false, vertical: true)
            if book.availability == .available, book.hasLongPart {
                Label("A file is over 35 hours. Q2 Pod may say it's too long to play; if it does, split the book into parts.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch placement {
            case .onQ2:      Label("On your Q2", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .nextSync:  Label("Copied at the next sync", systemImage: "arrow.down.circle").foregroundStyle(.secondary)
            case .notChosen: Label("Not chosen for your Q2", systemImage: "minus.circle").foregroundStyle(.secondary)
            case .cantSync, nil: EmptyView()
            }
        }
    }

    /// The book's files in play order, then where they are.
    private func partsSection(_ book: Audiobook) -> some View {
        let parts = book.parts.sorted { ($0.discNumber, $0.trackNumber) < ($1.discNumber, $1.trackNumber) }
        return VStack(alignment: .leading, spacing: 6) {
            Text(parts.count == 1 ? "File" : "Files").font(.headline)
            ForEach(parts, id: \.fileURL) { part in
                VStack(alignment: .leading, spacing: 1) {
                    Text(part.fileName).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(partDetails(part, multiDisc: Set(parts.map(\.discNumber)).count > 1))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.callout)
            }
            if let folder = parts.first?.fileURL.deletingLastPathComponent() {
                Text(folder.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(parts.map(\.fileURL))
                }
            }
        }
    }

    /// "Disc 1 · Track 3 · 1:02:10 · 58 MB", leaving out what's unknown.
    private func partDetails(_ part: AudiobookPart, multiDisc: Bool) -> String {
        var bits: [String] = []
        if multiDisc, part.discNumber > 0 { bits.append("Disc \(part.discNumber)") }
        if part.trackNumber > 0 { bits.append("Track \(part.trackNumber)") }
        if part.durationSeconds > 0 {
            bits.append(Duration.seconds(part.durationSeconds).formatted(.time(pattern: .hourMinuteSecond)))
        }
        bits.append(Int64(part.fileSize).formatted(.byteCount(style: .file)))
        return bits.joined(separator: " · ")
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
