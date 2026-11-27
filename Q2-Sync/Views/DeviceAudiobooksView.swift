//
//  DeviceAudiobooksView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The Q2's Audiobooks tab, like Finder's: "Sync audiobooks onto <Q2>",
//  then all audiobooks or only the ticked ones, from Apple Books, with a
//  search field above the list.
//
//  HOW IT FITS
//  Shown by `DeviceView`. Changes are edits until Apply (the Sync bar
//  below every tab), like the Music tab. Books come from
//  `AudiobookLibraryModel`; protected and not-downloaded books are listed
//  with the reason, and their tick boxes are dimmed.
//  Audiobooks need Q2 Pod (its Audiobooks row resumes books, has chapters
//  and keeps them out of music); on stock firmware the tab says so.
//

import SwiftUI

struct DeviceAudiobooksView: View {

    let connected: ConnectedDevice
    let devices: DeviceMonitor

    @Environment(AutoSyncController.self) private var autoSync

    @State private var accessProblem: String?
    @State private var showingSkipped = false
    @State private var searchText = ""

    private var model: AudiobookLibraryModel { autoSync.audiobooks }

    private var settings: AudiobookSelection {
        devices.shownSyncSettings?.audiobooks ?? connected.device.effectiveAudiobooks
    }

    var body: some View {
        Group {
            if connected.device.profile.audiobooksFolderName == nil {
                ContentUnavailableView {
                    Label("Audiobook Sync Needs Q2 Pod", systemImage: "book.closed")
                } description: {
                    Text("Stock firmware treats audiobooks as songs and doesn't remember your place, so Q2 Sync only syncs audiobooks to a Q2 running Q2 Pod.")
                }
            } else {
                switch model.access.status {
                case .notAllowed:
                    allowView(message: "Q2 Sync syncs audiobooks from Apple Books. To list them, allow Q2 Sync to read Apple Books' folder. It only reads it, and never changes your books.")
                case .unavailable(let message):
                    allowView(message: message)
                case .allowed:
                    booksView
                }
            }
        }
        .task { await model.load() }
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
    private var booksView: some View {
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
                Text("Add DRM-free audiobooks (such as .m4b files) to Apple Books with File › Add to Library, then come back here. Books that aren't downloaded to this Mac don't appear.")
            } actions: {
                Button("Check Again") { Task { await model.load() } }
            }
        case .loaded(let books):
            let shown = filtered(books)
            VStack(spacing: 0) {
                header
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        FilterTextField(text: $searchText, prompt: "Search Audiobooks", field: .audiobooksTab)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    Divider()
                    if shown.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        List(shown) { book in
                            AudiobookRow(book: book, settings: settings) { ticked in
                                // ⌘-click: every book shown takes this box's
                                // new state, like the Music tab and Finder.
                                let isForAll = NSApp.currentEvent?.modifierFlags.contains(.command) == true
                                let ids = isForAll ? Set(shown.map(\.id)) : [book.id]
                                devices.editSyncSettings { $0.audiobooks.setTicked(ticked, ids: ids, in: books) }
                            }
                        }
                        .listStyle(.inset(alternatesRowBackgrounds: true))
                    }
                }
                // Like Finder: audiobooks off dims everything below the box.
                .disabled(!settings.isEnabled)
                Divider()
                footer(books)
            }
        }
    }

    /// "Sync audiobooks onto [Q2]", then all or selected, like Finder.
    private var header: some View {
        SyncSectionHeader(
            title: "Sync audiobooks onto \(connected.device.name)",
            isEnabled: Binding(get: { settings.isEnabled },
                               set: { on in devices.editSyncSettings { $0.audiobooks.isEnabled = on } }),
            choice: Binding(get: { settings.includesAll },
                            set: { all in devices.editSyncSettings { $0.audiobooks.includesAll = all } }),
            options: [
                SyncChoiceOption(label: "All audiobooks", value: true),
                SyncChoiceOption(label: "Selected audiobooks", value: false),
            ]) {
            if !settings.isEnabled && hasQ2SyncBooks {
                SyncSectionNote(text: "Audiobooks are off. When you sync, the review lets you remove the books Q2 Sync put on this card.",
                                systemImage: "exclamationmark.triangle", color: .orange)
            } else {
                Text("Only books downloaded to this Mac are listed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help("Apple Books doesn't list books that are only in iCloud. Download a book in Apple Books to sync it.")
            }
        }
    }

    /// `true` if the card holds audiobooks Q2 Sync copied there.
    private var hasQ2SyncBooks: Bool {
        !(devices.cardManifest?.audiobooks?.isEmpty ?? true)
    }

    /// The books matching the search text (title or author).
    private func filtered(_ books: [Audiobook]) -> [Audiobook] {
        AudiobookSearch.filter(books, matching: searchText)
    }

    private func footer(_ books: [Audiobook]) -> some View {
        let chosen = settings.books(from: books)
        let skipped = settings.isEnabled
            ? books.filter { $0.availability != .available && (settings.includesAll || settings.bookIDs.contains($0.id)) }
            : books.filter { $0.availability != .available }
        let seconds = chosen.reduce(0) { $0 + $1.durationSeconds }
        let bytes = chosen.reduce(UInt64(0)) { $0 + $1.totalSize }
        return HStack(spacing: 12) {
            Image(systemName: "book.closed").foregroundStyle(.secondary)
            Text(pluralized(chosen.count, "audiobook")).fontWeight(.medium)
            if seconds >= 60 {
                Text(Duration.seconds(seconds)
                        .formatted(.units(allowed: [.days, .hours, .minutes], width: .narrow, maximumUnitCount: 2)))
                    .foregroundStyle(.secondary)
            }
            Text(Int64(bytes).formatted(ByteCountFormatStyle(style: .file))).foregroundStyle(.secondary)
            if !skipped.isEmpty {
                Button {
                    showingSkipped = true
                } label: {
                    Label("\(skipped.count.formatted()) can't be synced", systemImage: "exclamationmark.circle")
                }
                .buttonStyle(.link)
                .popover(isPresented: $showingSkipped, arrowEdge: .top) {
                    SkippedAudiobooksView(books: skipped)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// One book: tick box, title and author, length, size, and why it can't
/// be synced if it can't.
private struct AudiobookRow: View {

    let book: Audiobook
    let settings: AudiobookSelection
    let setTicked: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { settings.isTicked(book) }, set: setTicked))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(settings.includesAll || book.availability != .available)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title).lineLimit(1)
                if let author = book.author {
                    Text(author).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if book.availability != .available {
                Label(book.availability.audiobookReason, systemImage: book.availability.symbolName)
                    .foregroundStyle(book.availability.tint)
                    .font(.callout)
                    .help(book.availability.audiobookExplanation)
            } else if book.hasLongPart {
                Label("May be too long", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .help("A file of this book is over 35 hours. Q2 Pod may say it's too long to play; if it does, split it into parts.")
            }
            if book.durationSeconds >= 60 {
                Text(Duration.seconds(book.durationSeconds)
                        .formatted(.units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            }
            Text(Int64(book.totalSize).formatted(ByteCountFormatStyle(style: .file)))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

/// Popover listing chosen audiobooks that can't be synced, and why.
struct SkippedAudiobooksView: View {

    let books: [Audiobook]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Some audiobooks can't be synced").font(.headline)
            ForEach(books) { book in
                Label("\(book.title): \(book.availability.audiobookReason)", systemImage: book.availability.symbolName)
                    .foregroundStyle(book.availability.tint)
                    .help(book.availability.audiobookExplanation)
            }
            Text("Protected audiobooks, such as most from the Apple Books store, only play in Apple's apps.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(width: 360)
    }
}

extension TrackAvailability {

    /// Why an audiobook can't be synced, in a few words.
    var audiobookReason: String {
        switch self {
        case .available:    return "Available"
        case .cloudOnly:    return "Not downloaded"
        case .drmProtected: return "Protected (DRM)"
        case .fileMissing:  return "Missing file"
        case .unsupported:  return "Can't be read"
        }
    }

    /// A sentence for tooltips about an audiobook.
    var audiobookExplanation: String {
        switch self {
        case .available:
            return "Stored on this Mac and free to copy."
        case .cloudOnly:
            return "In Apple Books but not downloaded to this Mac. Download it in Apple Books to sync it."
        case .drmProtected:
            return "Protected (DRM), like most audiobooks bought in the Apple Books store. It only plays in Apple's apps, so it can't play on a Q2."
        case .fileMissing:
            return "Some of this book's files aren't on this Mac. Download it again in Apple Books."
        case .unsupported:
            return "Its files couldn't be read as audio, or aren't in Apple Books' folder."
        }
    }
}
