//
//  DevicePodcastsView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The Q2's Podcasts tab, shaped like the Audiobooks tab: "Sync podcasts
//  onto <Q2>", then all shows or only the ticked ones, "Unplayed only",
//  and the shows with the episodes the Podcasts app has downloaded, with a
//  search field above the list.
//
//  HOW IT FITS
//  Shown by `DeviceView`. Changes are edits until Apply (the Sync bar
//  below every tab). Shows come from `PodcastLibraryModel`. Video and
//  protected episodes are listed dimmed with the reason; played episodes
//  are dimmed while "Unplayed only" is on. Q2 Sync only reads the Podcasts
//  app, so episodes played on the Q2 stay unplayed on the Mac: the tab
//  says so. Podcasts need Q2 Pod (its Library › Podcasts browses and
//  resumes them); on stock firmware the tab says so.
//

import SwiftUI

struct DevicePodcastsView: View {

    let connected: ConnectedDevice
    let devices: DeviceMonitor

    @Environment(AutoSyncController.self) private var autoSync

    @State private var accessProblem: String?
    @State private var showingSkipped = false
    @State private var searchText = ""

    private var model: PodcastLibraryModel { autoSync.podcasts }

    private var settings: PodcastSelection {
        devices.shownSyncSettings?.podcasts ?? connected.device.effectivePodcasts
    }

    var body: some View {
        Group {
            if connected.device.profile.podcastsFolderName == nil {
                ContentUnavailableView {
                    Label("Podcast Sync Needs Q2 Pod", systemImage: "mic")
                } description: {
                    Text("Stock firmware treats podcast episodes as songs and doesn't remember your place, so Q2 Sync only syncs podcasts to a Q2 running Q2 Pod.")
                }
            } else {
                switch model.access.status {
                case .notAllowed:
                    allowView(message: "Q2 Sync syncs the episodes the Podcasts app has downloaded. To list them, allow Q2 Sync to read the Podcasts app's folder. It only reads it, and never changes your podcasts.")
                case .unavailable(let message):
                    allowView(message: message)
                case .allowed:
                    showsView
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

    // MARK: - Shows

    @ViewBuilder
    private var showsView: some View {
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
                Text("Q2 Sync syncs the episodes the Podcasts app has downloaded to this Mac. Download some episodes in the Podcasts app, then come back here.")
            } actions: {
                Button("Check Again") { Task { await model.load() } }
            }
        case .loaded(let shows):
            let shown = PodcastSearch.filter(shows, matching: searchText)
            VStack(spacing: 0) {
                header
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        FilterTextField(text: $searchText, prompt: "Search Podcasts", field: .podcastsTab)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    Divider()
                    if shown.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        List {
                            ForEach(shown) { show in
                                PodcastShowRow(show: show, settings: settings) { ticked in
                                    // ⌘-click: every show listed takes this box's
                                    // new state, like the other tabs and Finder.
                                    let isForAll = NSApp.currentEvent?.modifierFlags.contains(.command) == true
                                    let ids = isForAll ? Set(shown.map(\.id)) : [show.id]
                                    devices.editSyncSettings { $0.podcasts.setTicked(ticked, ids: ids) }
                                }
                                ForEach(show.episodes) { episode in
                                    PodcastTabEpisodeRow(episode: episode, settings: settings)
                                }
                            }
                        }
                        .listStyle(.inset(alternatesRowBackgrounds: true))
                    }
                }
                // Like Finder: podcasts off dims everything below the box.
                .disabled(!settings.isEnabled)
                Divider()
                footer(shows)
            }
        }
    }

    /// "Sync podcasts onto [Q2]", all or selected shows, Unplayed only.
    private var header: some View {
        SyncSectionHeader(
            title: "Sync podcasts onto \(connected.device.name)",
            isEnabled: Binding(get: { settings.isEnabled },
                               set: { on in devices.editSyncSettings { $0.podcasts.isEnabled = on } }),
            choice: Binding(get: { settings.includesAll },
                            set: { all in devices.editSyncSettings { $0.podcasts.includesAll = all } }),
            options: [
                SyncChoiceOption(label: "All shows", value: true),
                SyncChoiceOption(label: "Selected shows", value: false),
            ]) {
            Toggle("Unplayed only", isOn: Binding(
                get: { settings.unplayedOnly },
                set: { on in devices.editSyncSettings { $0.podcasts.unplayedOnly = on } }))
                .toggleStyle(.checkbox)
                .padding(.leading, 22)
                .disabled(!settings.isEnabled)
                .help("Leaves out episodes the Podcasts app has marked played. Episodes you're partway through still sync.")
            if !settings.isEnabled && hasQ2SyncEpisodes {
                SyncSectionNote(text: "Podcasts are off. When you sync, the review lets you remove the episodes Q2 Sync put on this card.",
                                systemImage: "exclamationmark.triangle", color: .orange)
            } else {
                Text("Only episodes downloaded in the Podcasts app are listed. Episodes you play on the Q2 aren't marked played on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Q2 Sync only reads the Podcasts app, never changes it. Mark an episode played on this Mac or your iPhone: once the Podcasts app removes its download, the next sync can remove it from the Q2.")
            }
        }
    }

    /// `true` if the card holds episodes Q2 Sync copied there.
    private var hasQ2SyncEpisodes: Bool {
        !(devices.cardManifest?.podcasts?.isEmpty ?? true)
    }

    private func footer(_ shows: [PodcastShow]) -> some View {
        let chosen = settings.episodes(from: shows)
        // Episodes in chosen shows that can't be copied (video, protected).
        let skipped = shows.flatMap(\.episodes).filter {
            !$0.canSync && (!settings.isEnabled || settings.includesAll || settings.showIDs.contains($0.showID))
        }
        let bytes = chosen.reduce(UInt64(0)) { $0 + $1.fileSize }
        return HStack(spacing: 12) {
            Image(systemName: "mic").foregroundStyle(.secondary)
            Text(pluralized(chosen.count, "episode")).fontWeight(.medium)
            Text(Int64(bytes).formatted(ByteCountFormatStyle(style: .file))).foregroundStyle(.secondary)
            if !skipped.isEmpty {
                Button {
                    showingSkipped = true
                } label: {
                    Label("\(skipped.count.formatted()) can't be synced", systemImage: "exclamationmark.circle")
                }
                .buttonStyle(.link)
                .popover(isPresented: $showingSkipped, arrowEdge: .top) {
                    SkippedPodcastEpisodesView(episodes: skipped)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// A show: tick box, title and author, episode count and size.
private struct PodcastShowRow: View {

    let show: PodcastShow
    let settings: PodcastSelection
    let setTicked: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { settings.isTicked(show) }, set: setTicked))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(settings.includesAll)
            VStack(alignment: .leading, spacing: 2) {
                Text(show.title).fontWeight(.medium).lineLimit(1)
                if let author = show.author {
                    Text(author).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(pluralized(show.episodes.count, "episode"))
                .foregroundStyle(.secondary)
            Text(Int64(show.totalSize).formatted(ByteCountFormatStyle(style: .file)))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

/// An episode under its show: date, title, played state, size, and why it
/// can't be synced if it can't. Dimmed when it won't be copied.
private struct PodcastTabEpisodeRow: View {

    let episode: PodcastEpisode
    let settings: PodcastSelection

    /// Left out only because it's played and "Unplayed only" is on.
    private var isSkippedAsPlayed: Bool {
        settings.unplayedOnly && episode.playState == .played
    }

    var body: some View {
        HStack(spacing: 10) {
            // Lines up with the show's title, past its tick box.
            Color.clear.frame(width: 16, height: 1)
            Text(episode.published?.formatted(date: .abbreviated, time: .omitted) ?? "")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 100, alignment: .leading)
            Text(episode.title).lineLimit(1)
            Spacer()
            if let reason = episode.unsyncableReason {
                Label(episode.isProtected ? "Protected" : "Video",
                      systemImage: episode.isProtected ? "lock.fill" : "film")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .help(reason)
            } else {
                switch episode.playState {
                case .played:
                    Text("Played").font(.callout).foregroundStyle(.secondary)
                        .help(isSkippedAsPlayed ? "Played in the Podcasts app, so it isn't synced while Unplayed only is on."
                                                : "Played in the Podcasts app.")
                case .inProgress:
                    Text("In progress").font(.callout).foregroundStyle(.secondary)
                case .unplayed:
                    EmptyView()
                }
            }
            Text(Int64(episode.fileSize).formatted(ByteCountFormatStyle(style: .file)))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)
        }
        .opacity(episode.canSync && !isSkippedAsPlayed ? 1 : 0.5)
        .padding(.vertical, 1)
    }
}

/// Popover listing downloaded episodes that can't be synced, and why.
struct SkippedPodcastEpisodesView: View {

    let episodes: [PodcastEpisode]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Some episodes can't be synced").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(episodes) { episode in
                        Label("\(episode.showTitle): \(episode.title)",
                              systemImage: episode.isProtected ? "lock.fill" : "film")
                            .help(episode.unsyncableReason ?? "")
                    }
                }
            }
            .frame(maxHeight: 240)
            Text("Video podcasts aren't synced yet. Protected episodes, such as some from paid subscriptions, only play in Apple's apps.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(width: 380)
    }
}
