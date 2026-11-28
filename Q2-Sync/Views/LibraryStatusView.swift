//
//  LibraryStatusView.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  A compact status box at the bottom of the sidebar that summarises the
//  library: loading spinner, error, song counts by availability, and the
//  result of the "Mac looks empty" safety check.
//
//  HOW IT FITS
//  Displayed at the bottom of the sidebar by `RootView`. Reads `LibraryModel` only.
//

import SwiftUI

/// Sidebar footer summarizing the library's state.
struct LibraryStatusView: View {

    /// The model to summarise.
    let library: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch library.state {
            case .idle:
                Label("Music library not read yet", systemImage: "circle.dashed")
                    .foregroundStyle(.secondary)
            case .loading:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Reading Music library…")
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    // No `fixedSize(vertical:)`: outside a scroll view it can
                    // make the window ask for a huge minimum height (see
                    // `CapacityBarView`). The box is already full width.
                Button("Try Again") { Task { await library.load() } }
                    .controlSize(.small)
            case .loaded:
                loadedSummary
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }

    /// Counts and health once a snapshot exists.
    @ViewBuilder
    private var loadedSummary: some View {
        if let snapshot = library.snapshot {
            let counts = snapshot.availabilityCounts
            Text("\(pluralized(snapshot.tracks.count, "song")) · \(pluralized(snapshot.playlists.count, "playlist"))")
                .fontWeight(.medium)

            // Show every category that isn't zero, e.g. "Not downloaded: 12".
            ForEach(TrackAvailability.allCases, id: \.self) { kind in
                if let count = counts[kind], count > 0 {
                    HStack {
                        Image(systemName: kind.symbolName).foregroundStyle(kind.tint)
                        Text("\(kind.shortName): \(count.formatted())")
                    }
                    .help(kind.explanation)
                }
            }

            HealthLabel(health: library.health, healthyText: "Library looks healthy")

            if let duration = library.lastLoadDuration {
                Text(ReadTimeWording.text(duration))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// "Library looks healthy" in green, or the reason it can't be trusted in red.
private struct HealthLabel: View {

    let health: LibraryHealth?
    let healthyText: String

    var body: some View {
        switch health {
        case .healthy?:
            Label(healthyText, systemImage: "checkmark.shield")
                .foregroundStyle(.green)
        case .unsafe(let reason)?:
            Label(reason, systemImage: "xmark.shield")
                .foregroundStyle(.red)
        case nil:
            EmptyView()
        }
    }
}

/// Sidebar footer for the Books browser: book count and size, and the
/// books that can't sync, by reason.
struct AudiobookStatusView: View {

    let model: AudiobookLibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch model.state {
            case .idle:
                Label(model.source == nil ? "Apple Books not allowed yet" : "Apple Books not read yet",
                      systemImage: "circle.dashed")
                    .foregroundStyle(.secondary)
            case .loading:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Reading Apple Books…")
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("Try Again") { Task { await model.load() } }
                    .controlSize(.small)
            case .loaded(let books):
                let bytes = books.reduce(UInt64(0)) { $0 + $1.totalSize }
                Text("\(pluralized(books.count, "audiobook")) · \(Int64(bytes).formatted(.byteCount(style: .file)))")
                    .fontWeight(.medium)
                // Every reason a book can't sync that isn't zero.
                ForEach(TrackAvailability.allCases.filter { $0 != .available }, id: \.self) { kind in
                    let count = books.count { $0.availability == kind }
                    if count > 0 {
                        HStack {
                            Image(systemName: kind.symbolName).foregroundStyle(kind.tint)
                            Text("\(kind.audiobookReason): \(count.formatted())")
                        }
                        .help(kind.audiobookExplanation)
                    }
                }
                HealthLabel(health: model.health, healthyText: "Apple Books looks healthy")
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }
}

/// The sidebar's footer on Podcasts › Episodes: how many episodes are
/// downloaded, and how many can't sync and why.
struct PodcastStatusView: View {

    let model: PodcastLibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch model.state {
            case .idle:
                Label(model.source == nil ? "Podcasts app not allowed yet" : "Podcasts app not read yet",
                      systemImage: "circle.dashed")
                    .foregroundStyle(.secondary)
            case .loading:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Reading the Podcasts app…")
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("Try Again") { Task { await model.load() } }
                    .controlSize(.small)
            case .loaded(let shows):
                let episodes = shows.flatMap(\.episodes)
                let bytes = episodes.reduce(UInt64(0)) { $0 + $1.fileSize }
                Text("\(pluralized(episodes.count, "episode")) · \(Int64(bytes).formatted(.byteCount(style: .file)))")
                    .fontWeight(.medium)
                Text(pluralized(shows.count, "show")).foregroundStyle(.secondary)
                let video = episodes.count { $0.kind == .video && !$0.isProtected }
                let protected = episodes.count(where: \.isProtected)
                if video > 0 {
                    Label("Video: \(video.formatted())", systemImage: "film")
                        .help("Video podcasts aren't synced yet.")
                }
                if protected > 0 {
                    Label("Protected: \(protected.formatted())", systemImage: "lock.fill")
                        .help("Protected episodes can't be copied.")
                }
                HealthLabel(health: model.health, healthyText: "Podcasts app looks healthy")
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }
}

/// The sidebar's footer on a Q2's page: one line for each source this Q2
/// syncs (Music, Books, Podcasts), each with its own state and health.
/// Clicking a line shows that source's browser. It shows the sources'
/// state, not sync progress (the sync sheet shows that).
struct DeviceSourcesStatusView: View {

    /// The Q2 whose sources are shown.
    let device: KnownDevice
    let library: LibraryModel
    let audiobooks: AudiobookLibraryModel
    let podcasts: PodcastLibraryModel
    let navigation: AppNavigation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let settings = device.syncSettings
            let syncsBooks = device.profile.audiobooksFolderName != nil && settings.audiobooks.isEnabled
            let syncsPodcasts = device.profile.podcastsFolderName != nil && settings.podcasts.isEnabled
            if !settings.music.isEnabled && !syncsBooks && !syncsPodcasts {
                Label("Nothing set to sync yet", systemImage: "circle.dashed")
                    .foregroundStyle(.secondary)
            }
            if settings.music.isEnabled {
                sourceLine(musicLine, to: .library(.artists))
            }
            if syncsBooks {
                sourceLine(booksLine(settings.audiobooks), to: .audiobooks)
            }
            if syncsPodcasts {
                sourceLine(podcastsLine, to: .podcasts)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }

    /// What one line says.
    private struct Line {
        var source: String
        var isReading = false
        /// The summary after the source name, e.g. "9,890 songs".
        var text: String
        var health: LibraryHealth?
        /// A problem reading it (shown in red, with Try Again on the page).
        var failure: String?
        var readTime: Duration?
    }

    /// One clickable line, plus the reason underneath when it needs attention.
    private func sourceLine(_ line: Line, to item: SidebarItem) -> some View {
        Button {
            navigation.selection = item
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if line.isReading {
                        ProgressView().controlSize(.mini)
                    }
                    Text(summary(line))
                        .lineLimit(2)
                }
                if let failure = line.failure {
                    Text(failure).foregroundStyle(.red)
                } else if case .unsafe(let reason) = line.health {
                    Text(reason).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Show \(line.source)")
    }

    /// "Music: 9,890 songs · looks healthy · read in 4s", with the health
    /// word colored.
    private func summary(_ line: Line) -> AttributedString {
        var text = AttributedString("\(line.source): ")
        text.font = .caption.weight(.medium)
        text += AttributedString(line.text)
        switch line.health {
        case .healthy?:
            var word = AttributedString(" · looks healthy")
            word.foregroundColor = .green
            text += word
        case .unsafe?:
            var word = AttributedString(" · needs attention")
            word.foregroundColor = .red
            text += word
        case nil:
            break
        }
        if let readTime = line.readTime, !line.isReading {
            var time = AttributedString(" · " + ReadTimeWording.text(readTime).lowercased())
            time.foregroundColor = .secondary
            text += time
        }
        return text
    }

    private var musicLine: Line {
        var line = Line(source: "Music", text: "")
        switch library.state {
        case .idle:
            line.text = "not read yet"
        case .loading:
            line.isReading = true
            line.text = library.snapshot.map { pluralized($0.tracks.count, "song") } ?? "reading…"
        case .failed(let message):
            line.text = "couldn't be read"
            line.failure = message
        case .loaded:
            line.text = library.snapshot.map { pluralized($0.tracks.count, "song") } ?? ""
            line.health = library.health
            line.readTime = library.lastLoadDuration
        }
        return line
    }

    private func booksLine(_ selection: AudiobookSelection) -> Line {
        var line = Line(source: "Books", isReading: audiobooks.isReading, text: "")
        switch audiobooks.state {
        case .idle:
            line.text = audiobooks.source == nil ? "not allowed yet" : "not read yet"
        case .loading:
            line.text = "reading…"
        case .failed(let message):
            line.text = "couldn't be read"
            line.failure = message
        case .loaded(let books):
            line.text = pluralized(books.count, "audiobook")
            line.health = audiobooks.health(for: selection)
        }
        return line
    }

    private var podcastsLine: Line {
        var line = Line(source: "Podcasts", isReading: podcasts.isReading, text: "")
        switch podcasts.state {
        case .idle:
            line.text = podcasts.source == nil ? "not allowed yet" : "not read yet"
        case .loading:
            line.text = "reading…"
        case .failed(let message):
            line.text = "couldn't be read"
            line.failure = message
        case .loaded(let shows):
            line.text = pluralized(shows.reduce(0) { $0 + $1.episodes.count }, "episode")
            line.health = podcasts.health
        }
        return line
    }
}

// MARK: - Presentation helpers for availability

extension TrackAvailability {

    /// A short label for lists, e.g. "Not downloaded".
    var shortName: String {
        switch self {
        case .available:    return "Files on this Mac"
        case .cloudOnly:    return "Not downloaded"
        case .drmProtected: return "Apple Music (protected)"
        case .fileMissing:  return "Missing file"
        case .unsupported:  return "Unsupported"
        }
    }

    /// A sentence for tooltips: what this kind means and whether it syncs.
    var explanation: String {
        switch self {
        case .available:
            return "Song files stored on this Mac. These are the songs Q2 Sync can copy to your Q2."
        case .cloudOnly:
            return "Your own songs that are in iCloud but not downloaded to this Mac. Download them in Music to sync them."
        case .drmProtected:
            return "Apple Music subscription songs (and old protected purchases). They're licensed for Apple's apps only, so they can't be copied to a Q2, even when downloaded."
        case .fileMissing:
            return "Music lists these songs, but their files aren't where it expects. Locate them in Music to sync them."
        case .unsupported:
            return "Not an audio file the Q2 can play."
        }
    }

    /// SF Symbol shown next to the label.
    var symbolName: String {
        switch self {
        case .available:    return "checkmark.circle.fill"
        case .cloudOnly:    return "icloud"
        case .drmProtected: return "lock.fill"
        case .fileMissing:  return "questionmark.folder"
        case .unsupported:  return "nosign"
        }
    }

    /// Color for the symbol. The normal state is gray; color is kept
    /// for what needs attention.
    var tint: Color {
        switch self {
        case .available:    return .secondary
        case .cloudOnly:    return .blue
        case .drmProtected: return .orange
        case .fileMissing:  return .red
        case .unsupported:  return .secondary
        }
    }
}

// MARK: - Shared wording and the "not read yet" placeholder

/// Words used wherever the Music library is read, so they stay consistent.
///
/// "Music library" means the library of the Music app on this Mac. It can
/// list Apple Music subscription songs and songs only in iCloud too, but
/// only song files stored on this Mac can be synced.
enum LibraryWording {

    /// Tooltip for Refresh Audiobooks.
    static let refreshAudiobooksHelp = "Re-read the audiobooks in Apple Books on this Mac. Only DRM-free books downloaded to this Mac can be copied to your Q2. Q2 Sync never changes your books."

    /// Tooltip for Refresh Podcasts.
    static let refreshPodcastsHelp = "Re-read the episodes the Podcasts app has downloaded to this Mac. Only audio episodes that aren't protected can be copied to your Q2. Q2 Sync never changes your podcasts."

    /// Tooltip for Refresh Music Library.
    static let refreshHelp = "Re-read the Music app's library on this Mac. Only song files stored on this Mac can be copied to your Q2, not Apple Music subscription songs. Q2 Sync never changes your library."
}

/// Placeholder shown until the Music library has been read: a spinner while
/// reading, the error with Try Again if it failed.
struct LibraryNotReadView: View {

    /// The model being read.
    let library: LibraryModel

    var body: some View {
        switch library.state {
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Read Your Music Library", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await library.load() } }
            }
        case .idle, .loading, .loaded:
            ContentUnavailableView {
                Label {
                    Text("Reading Your Music Library…")
                } icon: {
                    ProgressView()
                }
            } description: {
                Text("Q2 Sync copies the song files stored on this Mac. Apple Music subscription songs can't be copied. Your library is only read, never changed.")
            }
        }
    }
}
