//
//  DeviceProfile.swift
//  Q2-Sync › Core › Device
//
//  PURPOSE
//  Everything that depends on WHICH FIRMWARE the Q2 runs lives here, in one
//  place: folder names, the list of items the app must never touch,
//  playlist format, and the "update your library" reminder steps.
//
//  HOW IT FITS
//  The sync engine and UI never hard-code firmware details. They ask the
//  current `DeviceProfile`. To support a new firmware, add a new static
//  profile below (see docs/CODE_GUIDE.md › "Adding a device profile").
//
//  SOURCES (checked 2026-11-15)
//  • Shanling Q2 Quick Start Guide v1.0 (stock firmware).
//  • Q2 Pod README, docs/internals.md, docs/discovery.md and the
//    Q2 Pod User Guide for release 1.8.5 (https://github.com/DiamondBond/q2-pod),
//    which is GPL-3.0 licensed. We use facts from its documentation, not code.
//
//  Anything marked "UNVERIFIED" still needs checking on a real Q2.
//

import Foundation

/// The firmware running on the Q2.
enum FirmwareKind: String, Codable, Sendable, CaseIterable, Identifiable {
    /// DiamondBond's "Q2 Pod" custom firmware.
    case q2Pod
    /// Shanling's own firmware.
    case stock

    var id: String { rawValue }

    /// Name shown in the UI.
    var displayName: String {
        switch self {
        case .q2Pod: return "Q2 Pod"
        case .stock: return "Shanling (stock)"
        }
    }

    /// The profile to use for this firmware.
    var profile: DeviceProfile {
        switch self {
        case .q2Pod: return .q2Pod
        case .stock: return .stock
        }
    }
}

/// How song paths are written inside `.m3u` playlist files.
enum PlaylistPathStyle: Codable, Hashable, Sendable {
    /// An absolute path as the player sees it, e.g. `/mnt/mmc/Music/A/B/01 X.mp3`.
    /// The associated value is the card's mount point on the device.
    case absoluteDevicePath(mountPoint: String)
    /// A Windows-style path, e.g. `A:\Music\A\B\01 X.mp3`, as iTunes exporters write.
    case windowsDrive(letter: String)
}

/// How playlist files are written for a firmware.
///
/// Every field here is a guess until checked on a real Q2: export a
/// playlist on the device and compare (see docs/DEVICE_CHECKS.md). When a
/// format is confirmed, set `isVerifiedOnDevice` to `true`.
struct PlaylistFormat: Hashable, Sendable {

    /// File extension without the dot. The Q2 imports `.m3u` only.
    var fileExtension: String

    /// How each song's path is written.
    var pathStyle: PlaylistPathStyle

    /// Line ending. CRLF is used because Q2 Pod's guide says playlists
    /// "as iTunes exporters write them" import, and those use CRLF.
    var lineEnding: String

    /// Write the `#EXTM3U` header and an `#EXTINF` line per song. The Q2
    /// accepts comment lines only if they contain "#EXT".
    var includesExtendedInfo: Bool

    /// Start the file with a UTF-8 byte-order mark. Off: Q2 Pod reads
    /// plain UTF-8.
    var includesByteOrderMark: Bool

    /// `true` once this format has been confirmed on a real device.
    var isVerifiedOnDevice: Bool

    /// The format Q2 Pod's user guide documents (release 1.8.5): `.m3u`
    /// files of UTF-8 text with `/mnt/mmc/Music/…` paths.
    static let documentedQ2Format = PlaylistFormat(
        fileExtension: "m3u",
        pathStyle: .absoluteDevicePath(mountPoint: "/mnt/mmc"),
        lineEnding: "\r\n",
        includesExtendedInfo: true,
        includesByteOrderMark: false,
        isVerifiedOnDevice: false
    )

    /// The same format, confirmed on a Q2 running Q2 Pod 1.8.9 (2026-11-21):
    /// 32 playlists, including ones with thousands of songs, imported with
    /// every song in place.
    static let verifiedQ2PodFormat: PlaylistFormat = {
        var format = documentedQ2Format
        format.isVerifiedOnDevice = true
        return format
    }()
}

/// Firmware-specific rules and text for one kind of Q2.
///
/// A profile is a plain value with no behaviour of its own besides small
/// helpers, so it's easy to read, compare and test.
struct DeviceProfile: Hashable, Sendable {

    /// Which firmware this profile describes.
    let firmware: FirmwareKind

    // MARK: Card layout

    /// The single app-managed folder at the card root that holds all synced
    /// music, laid out as `Music/Artist/Album/Track`. Q2 Pod's own docs use
    /// `/mnt/mmc/Music/…` in their examples.
    let musicFolderName: String

    /// Hidden folder at the card root where the app keeps its own state:
    /// the sync manifest, logs, and the optional "trash" for removed songs.
    /// It starts with a dot so the player doesn't list it.
    let appStateFolderName: String

    /// Where the player imports `.m3u` playlists from (card root).
    let playlistFolderName: String

    // MARK: Playlists

    /// How playlist files are written. UNVERIFIED on a real device until
    /// `playlistFormat.isVerifiedOnDevice` is `true`.
    let playlistFormat: PlaylistFormat

    /// The player keeps at most this many imported playlists.
    let maximumPlaylists: Int

    /// Longest playlist name, in UTF-8 bytes, the player stores correctly.
    let maximumPlaylistNameBytes: Int

    // MARK: Reserved items

    /// Rules for items on the card the app must never modify, delete, or
    /// count as "card-only music".
    let reservedItems: ReservedItemRules

    // MARK: User-facing text

    /// How to make the Q2 pick up the new music, needed after every sync.
    let libraryScanStep: String

    /// How to import the playlists in the card's playlist folder.
    let playlistImportStep: String

    /// Where the user finds the installed firmware version on the Q2.
    let versionLocationHint: String

    /// Steps that make the Q2 show album covers that changed on the card
    /// (Q2 Sync's `cover.jpg` files added or removed). Shown after the
    /// library steps, as a cover refresh doesn't rescan the music. Empty
    /// when the firmware needs nothing extra.
    let coverRefreshSteps: [String]

    /// The menu that installs `update.tar` from the card, on THIS firmware
    /// (the one running now, before the update).
    let tfCardUpdateMenuPath: String

    /// Card path on the device itself (used for playlists and docs).
    let deviceMountPoint: String

    /// The card folder audiobooks go in, or `nil` if this firmware doesn't
    /// support syncing them. Q2 Pod: `Audiobooks` (its own Library row,
    /// resume and chapters). Stock: `nil` (not known to resume books).
    var audiobooksFolderName: String? = nil

    /// `true` if `components` (a card path split at "/") is inside the
    /// audiobooks folder and no deeper than `Audiobooks/<book>/<file>`:
    /// the only part of a reserved folder Q2 Sync may change. See
    /// `PathGuard.check(url:for:)` for what's allowed there.
    func isAudiobookItem(_ components: [String]) -> Bool {
        guard let name = audiobooksFolderName, let first = components.first,
              first.lowercased() == name.lowercased() else { return false }
        return components.count <= 3
    }

    /// The card folder podcast episodes go in, or `nil` if this firmware
    /// doesn't support syncing them. Q2 Pod: `Podcasts` (Library ›
    /// Podcasts, which resumes and keeps episodes out of music lists).
    /// Stock: `nil`.
    var podcastsFolderName: String? = nil

    /// `true` if `components` is inside the podcasts folder and no deeper
    /// than `Podcasts/<show>/<episode file>`. Like `isAudiobookItem`, the
    /// only other part of a reserved folder Q2 Sync may change.
    func isPodcastItem(_ components: [String]) -> Bool {
        guard let name = podcastsFolderName, let first = components.first,
              first.lowercased() == name.lowercased() else { return false }
        return components.count <= 3
    }

    /// The card folder photos go in, or `nil` if this firmware doesn't
    /// show them. Q2 Pod: `Photos` (Photos › All Photos, and one album per
    /// folder directly inside). Stock: `nil`.
    var photosFolderName: String? = nil

    /// `true` if `components` is inside the photos folder and no deeper
    /// than `Photos/<album>/<photo>`. Unlike books and shows, photos may
    /// also sit loose in the folder itself (`Photos/<photo>`), which is
    /// how Q2 Pod's All Photos shows photos in no album. See
    /// `PathGuard.check(url:for:)` for what's allowed there.
    func isPhotoItem(_ components: [String]) -> Bool {
        guard let name = photosFolderName, let first = components.first,
              first.lowercased() == name.lowercased() else { return false }
        return components.count <= 3
    }

    /// Image types Q2 Pod shows in Photos (its `photos.c`), lowercased.
    static let photoExtensions: Set<String> = ["jpg", "jpeg", "png"]

    /// What to do after a sync, in order: eject, update the Q2's library,
    /// then whatever else applies.
    ///
    /// - Parameters:
    ///   - connection: How the card is connected (words the eject step).
    ///   - includePlaylists: `true` if there are playlists to import.
    ///   - includeCovers: `true` if album covers changed on the card.
    /// - Returns: The steps, ready to number.
    func postSyncSteps(connection: CardConnection, includePlaylists: Bool, includeCovers: Bool) -> [String] {
        var steps = [connection.ejectStep, libraryScanStep]
        if includePlaylists { steps.append(playlistImportStep) }
        if includeCovers { steps += coverRefreshSteps }
        return steps
    }
}

// MARK: - Built-in profiles

extension DeviceProfile {

    /// Items both firmwares create or rely on. Shared so the two profiles
    /// can't drift apart by accident.
    private static let sharedReservedRootNames: Set<String> = [
        // Firmware update files (stock and Q2 Pod).
        "update.tar", "update.tar.part", "recovery-update",
        // Q2 Pod folders that add their own Library rows, or hold settings.
        "Q2Pod", "EQ", "Podcasts", "Audiobooks", "Photos", "Books", "Videos",
        "Radio", "lockscreenimage",
        // Q2 Pod log written to the card.
        "battery-log.txt",
        // Windows metadata folders, in case the card was used on a PC.
        "System Volume Information", "$RECYCLE.BIN",
    ]

    /// Names reserved wherever they appear on the card, not just at the root.
    private static let sharedReservedAnywhereNames: Set<String> = [
        // Q2 Pod's folder markers that hide/unhide a folder from the library.
        "database.ignore", "database.unignore",
    ]

    /// Q2 Pod custom firmware (https://github.com/DiamondBond/q2-pod).
    static let q2Pod = DeviceProfile(
        firmware: .q2Pod,
        musicFolderName: "Music",
        appStateFolderName: ".q2sync",
        playlistFolderName: "_explaylist_data",
        playlistFormat: .verifiedQ2PodFormat,
        maximumPlaylists: 100,
        maximumPlaylistNameBytes: 63,
        reservedItems: ReservedItemRules(
            reservedRootNames: sharedReservedRootNames,
            reservedAnywhereNames: sharedReservedAnywhereNames,
            reservedNameFragments: ["librespot"],
            appOwnedHiddenNames: [".q2sync"]
        ),
        libraryScanStep: "On the Q2, choose Library → Update Library → Scan music now.",
        playlistImportStep: "To bring in playlists, choose Library → Playlists → Import.",
        versionLocationHint: "On the Q2, open System settings → About and look for “CFW. Version”.",
        // Q2 Pod 1.4.3 and later (DiamondBond's): the Refresh tile at the end
        // of Cover Flow was removed; the Display setting does the same,
        // applied the next time Cover Flow opens.
        coverRefreshSteps: [
            "To show the new album covers, choose System settings → Display → Coverflow → Refresh Coverflow (it also redoes the album covers in Library).",
            "Open Cover Flow: the covers rebuild then.",
        ],
        tfCardUpdateMenuPath: "System settings → System Update → TF card update",
        deviceMountPoint: "/mnt/mmc",
        audiobooksFolderName: "Audiobooks",
        podcastsFolderName: "Podcasts",
        photosFolderName: "Photos"
    )

    /// Shanling's stock firmware. It shares the card layout with Q2 Pod,
    /// which keeps stock's playlist folder "as it is".
    static let stock = DeviceProfile(
        firmware: .stock,
        musicFolderName: "Music",
        appStateFolderName: ".q2sync",
        playlistFolderName: "_explaylist_data",
        playlistFormat: .documentedQ2Format, // UNVERIFIED on stock: same folder, assumed same format
        maximumPlaylists: 100,
        maximumPlaylistNameBytes: 63,
        reservedItems: ReservedItemRules(
            reservedRootNames: sharedReservedRootNames,
            reservedAnywhereNames: sharedReservedAnywhereNames,
            reservedNameFragments: ["librespot"],
            appOwnedHiddenNames: [".q2sync"]
        ),
        libraryScanStep: "On the Q2, choose Local Songs → Update Library → Scan music now.",
        playlistImportStep: "To bring in playlists, open Playlists and choose Import.", // UNVERIFIED wording on stock
        versionLocationHint: "On the Q2, open System Setting → About.",
        coverRefreshSteps: [], // UNVERIFIED: whether stock's album grid needs a refresh
        // UNVERIFIED wording on stock. Q2 Pod's docs say it reuses stock's
        // System Update page, whose first button is the TF card update.
        tfCardUpdateMenuPath: "System Setting → System Update → TF card update",
        deviceMountPoint: "/mnt/mmc"
    )
}
