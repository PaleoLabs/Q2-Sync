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

/// Sidebar footer summarising the library's state.
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
                    .fixedSize(horizontal: false, vertical: true)
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
            Text("\(snapshot.tracks.count.formatted()) songs · \(snapshot.playlists.count.formatted()) playlists")
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

            if let health = library.health {
                switch health {
                case .healthy:
                    Label("Library looks healthy", systemImage: "checkmark.shield")
                        .foregroundStyle(.green)
                case .unsafe(let reason):
                    Label(reason, systemImage: "xmark.shield")
                        .foregroundStyle(.red)
                }
            }

            if let duration = library.lastLoadDuration {
                Text("Read in \(duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))")
                    .foregroundStyle(.tertiary)
            }
        }
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

    /// Accent colour for the symbol.
    var tint: Color {
        switch self {
        case .available:    return .green
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
