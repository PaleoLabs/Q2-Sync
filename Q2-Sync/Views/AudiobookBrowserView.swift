//
//  AudiobookBrowserView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The sidebar's Audiobooks › Books page: every audiobook in Apple Books in
//  one table (title, author, length, size) and where it stands with the Q2:
//  on it, copied at the next sync, not chosen, or why it can't sync. From
//  the Mac-side record of the card, so it works while the Q2 is unplugged.
//  The toolbar's search field narrows the table; Book Info (⌘I) shows the
//  selected book's details. Read-only; choosing books happens on the Q2's
//  Audiobooks tab.
//
//  HOW IT FITS
//  Shown by `RootView` when Books is selected. The sidebar section shows
//  while any Q2 syncs audiobooks (#70). The template for later kinds
//  (podcasts, videos): one sidebar section, a browser and an info panel.
//

import AppKit
import SwiftUI

extension FocusedValues {
    /// `true` when the frontmost window shows the Books browser (read by
    /// `SongInfoCommands` to offer Show Book Info).
    @Entry var offersBookInfo: Bool?
}

/// Browses the audiobooks in Apple Books against the Q2.
struct AudiobookBrowserView: View {

    let devices: DeviceMonitor

    @Environment(AutoSyncController.self) private var autoSync

    /// The selected books.
    @State private var selection: Set<Audiobook.ID> = []

    /// Column sorting; by title to start with, like the Audiobooks tab.
    @State private var sortOrder = [KeyPathComparator(\Audiobook.title, comparator: .localizedStandard)]

    /// Whether the book inspector is open (remembered across launches).
    @AppStorage("showBookInfo") private var showBookInfo = false

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var accessProblem: String?

    private var model: AudiobookLibraryModel { autoSync.audiobooks }

    /// The Q2 compared with, and its books.
    private var marks: AudiobookMarks {
        let reference = devices.referenceContents
        return AudiobookMarks(record: reference?.record, selection: reference?.device.effectiveAudiobooks)
    }

    var body: some View {
        Group {
            switch model.access.status {
            case .notAllowed:
                allowView(message: "Q2 Sync syncs audiobooks from Apple Books. To list them, allow Q2 Sync to read Apple Books' folder. It only reads it, and never changes your books.")
            case .unavailable(let message):
                allowView(message: message)
            case .allowed:
                content
            }
        }
        .navigationTitle("Books")
        .navigationSubtitle(comparisonSubtitle)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search Books")
        .searchFocused($isSearchFocused)
        // Edit › Find (⌘F) puts the cursor in the search field.
        .onAppear { autoSync.navigation.filterAppeared(.library) }
        .onDisappear { autoSync.navigation.filterDisappeared(.library) }
        .onChange(of: autoSync.navigation.findRequests) {
            if autoSync.navigation.filterField == .library { isSearchFocused = true }
        }
        .task { await model.load() }
        // Enables View › Show Book Info while this view is showing.
        .focusedSceneValue(\.offersBookInfo, true)
        .inspector(isPresented: $showBookInfo) {
            let book = selection.count == 1 ? model.books.first { selection.contains($0.id) } : nil
            BookInspectorView(book: book, selectedCount: selection.count,
                              placement: book.flatMap { marks.placement(of: $0) })
                .inspectorColumnWidth(min: 220, ideal: 260, max: 300)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $showBookInfo) {
                    Label("Book Info", systemImage: "info.circle")
                }
                .labelStyle(.titleAndIcon)
                .help("Show or hide details of the selected book (⌘I)")
            }
        }
        .alert("Couldn't Allow Access", isPresented: Binding(get: { accessProblem != nil },
                                                             set: { if !$0 { accessProblem = nil } })) {
            Button("OK") { accessProblem = nil }
        } message: {
            Text(accessProblem ?? "")
        }
    }

    // MARK: - Access

    private func allowView(message: String) -> some View {
        ContentUnavailableView {
            Label("Audiobooks from Apple Books", systemImage: "book.closed")
        } description: {
            Text(message)
        } actions: {
            Button("Allow Access to Books…") {
                Task { accessProblem = await model.allowAccess() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Books

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Reading Apple Books…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Apple Books Couldn't Be Read", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await model.load() } }
            }
        case .loaded(let books) where books.isEmpty:
            ContentUnavailableView {
                Label("No Audiobooks in Apple Books", systemImage: "book.closed")
            } description: {
                Text("Add DRM-free audiobooks (such as .m4b files) to Apple Books with File › Add to Library. Books that aren't downloaded to this Mac don't appear.")
            } actions: {
                Button("Check Again") { Task { await model.load() } }
            }
        case .loaded(let books):
            let shown = AudiobookSearch.filter(books, matching: searchText).sorted(using: sortOrder)
            if shown.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                table(shown)
            }
        }
    }

    private func table(_ books: [Audiobook]) -> some View {
        let marks = marks
        return Table(books, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Title", value: \.title, comparator: .localizedStandard) { book in
                Text(book.title).help(book.title)
            }
            .width(min: 160, ideal: 260)
            TableColumn("Author", value: \.authorSortKey, comparator: .localizedStandard) { book in
                Text(book.author ?? "").foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 160)
            TableColumn("Length", value: \.durationSeconds) { book in
                Text(book.lengthText).monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 70, max: 90)
            TableColumn("Size", value: \.totalSize) { book in
                Text(Int64(book.totalSize).formatted(.byteCount(style: .file)))
                    .monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 75, max: 90)
            TableColumn("Q2") { book in
                BookStatusLabel(book: book, placement: marks.placement(of: book))
            }
            .width(min: 120, ideal: 170)
        }
        .contextMenu(forSelectionType: Audiobook.ID.self) { ids in
            Button("Show Info") {
                selection = ids
                showBookInfo = true
            }
            .disabled(ids.isEmpty)
            Button("Show in Finder") { showInFinder(ids, in: books) }
                .disabled(ids.isEmpty)
        } primaryAction: { ids in
            // Double-click, like the song table.
            selection = ids
            showBookInfo.toggle()
        }
    }

    /// Reveals the selected books' files (their first part each).
    private func showInFinder(_ ids: Set<Audiobook.ID>, in books: [Audiobook]) {
        let files = books.filter { ids.contains($0.id) }.compactMap(\.parts.first?.fileURL)
        guard !files.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(files)
    }

    /// "Compared with Shanling-Q2 · as of Nov 22, 10:14", or a hint.
    private var comparisonSubtitle: String {
        guard case .loaded = model.state else { return "" }
        guard let reference = devices.referenceContents, reference.record.audiobookIDs != nil else {
            return "Connect your Q2 to see which books are on it"
        }
        let when = reference.record.checkedAt.formatted(date: .abbreviated, time: .shortened)
        return devices.connected?.device.volumeUUID == reference.device.volumeUUID
            ? "Compared with \(reference.device.name)"
            : "Compared with \(reference.device.name) · as of \(when)"
    }
}

/// A book's place with the Q2, or why it can't sync.
struct BookStatusLabel: View {
    let book: Audiobook
    let placement: TrackPlacement?

    var body: some View {
        switch placement {
        case .onQ2:
            Label("On Q2", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .nextSync:
            Label("Next sync", systemImage: "arrow.down.circle").foregroundStyle(.secondary)
                .help("Copied to the Q2 at the next sync.")
        case .notChosen:
            Label("Not chosen", systemImage: "minus.circle").foregroundStyle(.secondary)
                .help("Not chosen on the Q2's Audiobooks tab.")
        case .cantSync:
            Label(book.availability.audiobookReason, systemImage: book.availability.symbolName)
                .foregroundStyle(book.availability.tint)
                .help(book.availability.audiobookExplanation)
        case nil:
            EmptyView()
        }
    }
}

extension Audiobook {
    /// The author for sorting; books without one sort first.
    var authorSortKey: String { author ?? "" }

    /// "11h 3m", or "" under a minute.
    var lengthText: String {
        guard durationSeconds >= 60 else { return "" }
        return Duration.seconds(durationSeconds)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2))
    }
}
