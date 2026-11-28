//
//  PodcastBrowserView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The sidebar's Podcasts › Episodes page: every episode the Podcasts app
//  has downloaded in one table (show, title, date, played, size) and where
//  it stands with the Q2: on it, copied at the next sync, not chosen, or
//  why it can't sync. From the Mac-side record of the card, so it works
//  while the Q2 is unplugged. The toolbar's search field narrows the
//  table; Episode Info (⌘I) shows the selected episode's details.
//  Read-only; choosing shows happens on the Q2's Podcasts tab.
//
//  HOW IT FITS
//  Shown by `RootView` when Episodes is selected. The sidebar section
//  shows while any Q2 syncs podcasts (#70). Built from the template of
//  `AudiobookBrowserView`.
//

import AppKit
import SwiftUI

extension FocusedValues {
    /// `true` when the frontmost window shows the Episodes browser (read by
    /// `SongInfoCommands` to offer Show Episode Info).
    @Entry var offersEpisodeInfo: Bool?
}

/// Browses the Podcasts app's downloaded episodes against the Q2.
struct PodcastBrowserView: View {

    let devices: DeviceMonitor

    @Environment(AutoSyncController.self) private var autoSync

    /// The selected episodes.
    @State private var selection: Set<PodcastEpisode.ID> = []

    /// Column sorting; newest first to start with, like the Podcasts app.
    @State private var sortOrder = [KeyPathComparator(\PodcastEpisode.publishedSortKey, order: .reverse)]

    /// Whether the episode inspector is open (remembered across launches).
    @AppStorage("showEpisodeInfo") private var showEpisodeInfo = false

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var accessProblem: String?

    private var model: PodcastLibraryModel { autoSync.podcasts }

    /// The Q2 compared with, and its episodes.
    private var marks: PodcastMarks {
        let reference = devices.referenceContents
        return PodcastMarks(record: reference?.record, selection: reference?.device.effectivePodcasts)
    }

    var body: some View {
        Group {
            switch model.access.status {
            case .notAllowed:
                allowView(message: "Q2 Sync syncs the episodes the Podcasts app has downloaded. To list them, allow Q2 Sync to read the Podcasts app's folder. It only reads it, and never changes your podcasts.")
            case .unavailable(let message):
                allowView(message: message)
            case .allowed:
                content
            }
        }
        .navigationTitle("Episodes")
        .navigationSubtitle(comparisonSubtitle)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search Podcasts")
        .searchFocused($isSearchFocused)
        // Edit › Find (⌘F) puts the cursor in the search field.
        .onAppear { autoSync.navigation.filterAppeared(.library) }
        .onDisappear { autoSync.navigation.filterDisappeared(.library) }
        .onChange(of: autoSync.navigation.findRequests) {
            if autoSync.navigation.filterField == .library { isSearchFocused = true }
        }
        .task { await model.load() }
        // Enables View › Show Episode Info while this view is showing.
        .focusedSceneValue(\.offersEpisodeInfo, true)
        .inspector(isPresented: $showEpisodeInfo) {
            let episode = selection.count == 1 ? episodes.first { selection.contains($0.id) } : nil
            EpisodeInspectorView(episode: episode, selectedCount: selection.count,
                                 placement: episode.flatMap { marks.placement(of: $0) })
                .inspectorColumnWidth(min: 220, ideal: 260, max: 300)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $showEpisodeInfo) {
                    Label("Episode Info", systemImage: "info.circle")
                }
                .labelStyle(.titleAndIcon)
                .help("Show or hide details of the selected episode (⌘I)")
            }
        }
        .alert("Couldn't Allow Access", isPresented: Binding(get: { accessProblem != nil },
                                                             set: { if !$0 { accessProblem = nil } })) {
            Button("OK") { accessProblem = nil }
        } message: {
            Text(accessProblem ?? "")
        }
    }

    /// Every downloaded episode, from every show.
    private var episodes: [PodcastEpisode] { model.shows.flatMap(\.episodes) }

    // MARK: - Access

    private func allowView(message: String) -> some View {
        ContentUnavailableView {
            Label("Podcasts from the Podcasts App", systemImage: "mic")
        } description: {
            Text(message)
        } actions: {
            Button("Allow Access to Podcasts…") {
                Task { accessProblem = await model.allowAccess() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Episodes

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Reading the Podcasts app…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("The Podcasts App Couldn't Be Read", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await model.load() } }
            }
        case .loaded(let shows) where shows.isEmpty:
            ContentUnavailableView {
                Label("No Downloaded Episodes", systemImage: "mic")
            } description: {
                Text("Download episodes in the Podcasts app, then come back here. Episodes that aren't downloaded to this Mac don't appear.")
            } actions: {
                Button("Check Again") { Task { await model.load() } }
            }
        case .loaded(let shows):
            let shown = PodcastSearch.filter(shows, matching: searchText).flatMap(\.episodes).sorted(using: sortOrder)
            if shown.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                table(shown)
            }
        }
    }

    private func table(_ episodes: [PodcastEpisode]) -> some View {
        let marks = marks
        return Table(episodes, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Show", value: \.showTitle, comparator: .localizedStandard) { episode in
                Text(episode.showTitle).foregroundStyle(.secondary).help(episode.showTitle)
            }
            .width(min: 100, ideal: 160)
            TableColumn("Title", value: \.title, comparator: .localizedStandard) { episode in
                Text(episode.title).help(episode.title)
            }
            .width(min: 160, ideal: 300)
            TableColumn("Date", value: \.publishedSortKey) { episode in
                Text(episode.published?.formatted(date: .abbreviated, time: .omitted) ?? "")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 95, ideal: 105, max: 125)
            TableColumn("Played", value: \.playStateSortKey) { episode in
                Text(episode.playState.label).foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80, max: 100)
            TableColumn("Size", value: \.fileSize) { episode in
                Text(Int64(episode.fileSize).formatted(.byteCount(style: .file)))
                    .monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 75, max: 90)
            TableColumn("Q2") { episode in
                EpisodeStatusLabel(episode: episode, placement: marks.placement(of: episode))
            }
            .width(min: 120, ideal: 150)
        }
        .contextMenu(forSelectionType: PodcastEpisode.ID.self) { ids in
            Button("Show Info") {
                selection = ids
                showEpisodeInfo = true
            }
            .disabled(ids.isEmpty)
            Button("Show in Finder") { showInFinder(ids, in: episodes) }
                .disabled(ids.isEmpty)
        } primaryAction: { ids in
            // Double-click, like the song and book tables.
            selection = ids
            showEpisodeInfo.toggle()
        }
    }

    /// Reveals the selected episodes' downloaded files.
    private func showInFinder(_ ids: Set<PodcastEpisode.ID>, in episodes: [PodcastEpisode]) {
        let files = episodes.filter { ids.contains($0.id) }.map(\.fileURL)
        guard !files.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(files)
    }

    /// "Compared with Shanling-Q2 · as of Nov 22, 10:14", or a hint.
    private var comparisonSubtitle: String {
        guard case .loaded = model.state else { return "" }
        guard let reference = devices.referenceContents, reference.record.podcastEpisodeIDs != nil else {
            return "Connect your Q2 to see which episodes are on it"
        }
        let when = reference.record.checkedAt.formatted(date: .abbreviated, time: .shortened)
        return devices.connected?.device.volumeUUID == reference.device.volumeUUID
            ? "Compared with \(reference.device.name)"
            : "Compared with \(reference.device.name) · as of \(when)"
    }
}

/// An episode's place with the Q2, or why it can't sync.
struct EpisodeStatusLabel: View {
    let episode: PodcastEpisode
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
                .help(episode.playState == .played
                      ? "Not chosen on the Q2's Podcasts tab, or played while Unplayed only is on."
                      : "Not chosen on the Q2's Podcasts tab.")
        case .cantSync:
            Label(episode.isProtected ? "Protected" : "Video",
                  systemImage: episode.isProtected ? "lock.fill" : "film")
                .foregroundStyle(.secondary)
                .help(episode.unsyncableReason ?? "")
        case nil:
            EmptyView()
        }
    }
}

extension PodcastEpisode {
    /// The date for sorting; undated episodes sort as oldest.
    var publishedSortKey: Date { published ?? .distantPast }

    /// Unplayed, in progress, played: for sorting the Played column.
    var playStateSortKey: Int {
        switch playState {
        case .unplayed:   return 0
        case .inProgress: return 1
        case .played:     return 2
        }
    }
}

extension PodcastPlayState {
    /// "Played", "In progress", or "" when unplayed (the usual case).
    var label: String {
        switch self {
        case .played:     return "Played"
        case .inProgress: return "In progress"
        case .unplayed:   return ""
        }
    }
}
