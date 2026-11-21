//
//  PodDataBackup.swift
//  Q2-Sync › Core › Device
//
//  PURPOSE
//  Backs up the personal data Q2 Pod keeps ON THE CARD (ratings, listens
//  not yet scrobbled, scrobbling and radio settings, EQ presets, custom App
//  Store sources, Rockbox settings) to the Mac, and puts it back on a card.
//  It protects against a lost, failed or reformatted card.
//
//  WHAT IT CAN'T BACK UP
//  Q2 Pod's and stock's device settings live in the Q2's own flash
//  (`/mnt/data/config.ini`), which a Mac can't see over USB Storage. A
//  firmware update doesn't touch the card at all.
//
//  WHERE (checked 2026-11-21, Q2 Pod docs/internals.md)
//      .ratings.tsv              song ratings
//      .scrobbler.log            listens not yet sent to Last.fm/ListenBrainz
//      .scrobble.ini             scrobbling settings
//      Radio/favourites.m3u      radio favourites
//      EQ/                       EQ presets to import
//      .q2/custom-sources.list   your extra App Store sources
//      .rockbox/config.cfg       Rockbox settings
//
//  SAFETY
//  • Backup only READS the card and writes only inside
//    ~/Downloads/Q2 Sync Backups (never ~/Music).
//  • Restore writes only the paths above, through
//    `PathGuard.checkPodDataPath`, and only those you tick.
//

import Foundation

/// One kind of Q2 Pod data on the card.
struct PodDataItem: Sendable, Hashable, Identifiable {
    /// Path on the card.
    let path: CardPath
    /// `true` for a folder (backed up with everything inside).
    let isFolder: Bool
    /// What it is, for people.
    let label: String
    /// Ticked by default when restoring.
    let restoreByDefault: Bool
    /// A caution shown when restoring, if any.
    let restoreWarning: String?
    var id: CardPath { path }
}

/// What a backup holds, saved beside it as `backup.json`.
struct PodDataBackupInfo: Codable, Sendable, Equatable {
    /// One backed-up file.
    struct File: Codable, Sendable, Equatable {
        let path: CardPath
        let size: UInt64
    }
    var created: Date
    var deviceName: String
    var volumeUUID: String
    var files: [File]
    /// Where the backup is on the Mac (not saved).
    var folder: URL?

    private enum CodingKeys: String, CodingKey { case created, deviceName, volumeUUID, files }

    /// The items (from `PodDataBackup.items`) this backup has files for.
    var items: [PodDataItem] {
        PodDataBackup.items.filter { item in files.contains { PodDataBackup.belongs($0.path, to: item) } }
    }
}

/// Problems backing up or restoring.
enum PodDataError: LocalizedError, Equatable {
    case nothingToBackUp
    case destinationRefused(String)
    case notABackup
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .nothingToBackUp: return "There's no Q2 Pod data on this card to back up yet."
        case .destinationRefused(let path): return "Refused to write outside the backup folder: \(path)"
        case .notABackup: return "This folder isn't a Q2 Sync backup (it has no backup.json)."
        case .tooLarge: return "Q2 Pod's data on this card is unexpectedly large, so it wasn't backed up."
        }
    }
}

/// Backing up and restoring Q2 Pod's data.
enum PodDataBackup {

    /// Everything that's backed up.
    static let items: [PodDataItem] = [
        PodDataItem(path: ".ratings.tsv", isFolder: false, label: "Song ratings", restoreByDefault: true,
                    restoreWarning: nil),
        PodDataItem(path: ".scrobbler.log", isFolder: false, label: "Listens not yet scrobbled",
                    restoreByDefault: false,
                    restoreWarning: "Restoring old listens can send them to Last.fm or ListenBrainz twice."),
        PodDataItem(path: ".scrobble.ini", isFolder: false, label: "Scrobbling settings", restoreByDefault: true,
                    restoreWarning: nil),
        PodDataItem(path: "Radio/favourites.m3u", isFolder: false, label: "Radio favourites", restoreByDefault: true,
                    restoreWarning: nil),
        PodDataItem(path: "EQ", isFolder: true, label: "EQ presets", restoreByDefault: true, restoreWarning: nil),
        PodDataItem(path: ".q2/custom-sources.list", isFolder: false, label: "Custom App Store sources",
                    restoreByDefault: true, restoreWarning: nil),
        PodDataItem(path: ".rockbox/config.cfg", isFolder: false, label: "Rockbox settings", restoreByDefault: true,
                    restoreWarning: nil),
    ]

    /// The most a backup may hold (the real data is a few megabytes).
    static let maximumBytes: UInt64 = 200 * 1024 * 1024

    /// Where backups go: ~/Downloads/Q2 Sync Backups (the real Downloads,
    /// not the sandbox container's).
    static var backupsFolder: URL {
        PathGuard.realHomeDirectory.appending(path: "Downloads/Q2 Sync Backups", directoryHint: .isDirectory)
    }

    /// `true` if a card path is this item or inside it (case-insensitive).
    static func belongs(_ path: CardPath, to item: PodDataItem) -> Bool {
        let lower = path.lowercased(), itemPath = item.path.lowercased()
        return lower == itemPath || (item.isFolder && lower.hasPrefix(itemPath + "/"))
    }

    /// The Q2 Pod data files on a card (plain files only; symlinks and
    /// macOS `._` files are skipped).
    ///
    /// - Parameter cardRoot: The card's root.
    /// - Returns: Card paths with sizes.
    static func filesOnCard(cardRoot: URL) -> [PodDataBackupInfo.File] {
        var files: [PodDataBackupInfo.File] = []
        for item in items {
            let url = cardRoot.appending(path: item.path)
            if item.isFolder {
                guard let enumerator = FileManager.default.enumerator(
                    at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { continue }
                for case let file as URL in enumerator {
                    guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                          values.isRegularFile == true, values.isSymbolicLink != true,
                          !file.lastPathComponent.hasPrefix("._") else { continue }
                    let relative = String(file.standardizedFileURL.path.dropFirst(cardRoot.standardizedFileURL.path.count + 1))
                    files.append(.init(path: relative, size: UInt64(values.fileSize ?? 0)))
                }
            } else if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                      values.isRegularFile == true, values.isSymbolicLink != true {
                files.append(.init(path: item.path, size: UInt64(values.fileSize ?? 0)))
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    /// Copies Q2 Pod's data from the card into a new dated folder.
    ///
    /// - Parameters:
    ///   - cardRoot: The card (only read).
    ///   - deviceName / volumeUUID: Recorded in `backup.json`.
    ///   - backupsFolder: Where backups go.
    ///   - protectedFolders: Mac folders never written (~/Music…).
    /// - Returns: What was backed up, with `folder` set.
    /// - Throws: `PodDataError` or file errors. A partial backup is removed.
    static func backUp(cardRoot: URL, deviceName: String, volumeUUID: String,
                       to backupsFolder: URL = backupsFolder, protectedFolders: [URL]) throws -> PodDataBackupInfo {
        let files = filesOnCard(cardRoot: cardRoot)
        guard !files.isEmpty else { throw PodDataError.nothingToBackUp }
        guard files.reduce(0, { $0 + $1.size }) <= maximumBytes else { throw PodDataError.tooLarge }

        let created = Date.now
        let stamp = SyncLog.timestamp(created) // e.g. "2026-11-21 at 16.40.05"
        let safeName = FilenameSanitizer.sanitizeComponent(deviceName, fallback: "Q2")
        try FileManager.default.createDirectory(at: backupsFolder, withIntermediateDirectories: true)
        var folderName = "\(safeName) \(stamp)"
        var number = 2
        while FileManager.default.fileExists(atPath: backupsFolder.appending(path: folderName).path) {
            folderName = "\(safeName) \(stamp) (\(number))"; number += 1
        }
        let folder = try checkedDestination(folderName, in: backupsFolder, protectedFolders: protectedFolders)

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            for file in files {
                let destination = try checkedDestination("\(folderName)/\(file.path)", in: backupsFolder,
                                                         protectedFolders: protectedFolders)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: cardRoot.appending(path: file.path), to: destination)
            }
            var info = PodDataBackupInfo(created: created, deviceName: deviceName, volumeUUID: volumeUUID, files: files)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(info).write(to: folder.appending(path: "backup.json"))
            let readme = """
            Q2 Pod data from “\(deviceName)”, backed up by Q2 Sync on \(created.formatted()).

            Most of these files start with a dot, so Finder hides them (press ⌘⇧. to show them).
            To put them back on a card, use Q2 Sync › your Q2 › Settings › Q2 Pod Data › Restore.

            \(files.map { "\($0.path)  (\($0.size.formatted(.byteCount(style: .file))))" }.joined(separator: "\n"))

            """
            try Data(readme.utf8).write(to: folder.appending(path: "About this backup.txt"))
            info.folder = folder
            return info
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// Reads a backup's `backup.json`.
    static func readBackup(at folder: URL) throws -> PodDataBackupInfo {
        guard let data = try? Data(contentsOf: folder.appending(path: "backup.json")) else {
            throw PodDataError.notABackup
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var info = try decoder.decode(PodDataBackupInfo.self, from: data)
        info.folder = folder
        return info
    }

    /// The backups in the backups folder, newest first.
    static func existingBackups(in backupsFolder: URL = backupsFolder) -> [PodDataBackupInfo] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: backupsFolder, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { try? readBackup(at: $0) }.sorted { $0.created > $1.created }
    }

    /// A path inside the backups folder, refusing anything outside it or in
    /// a protected folder (same rules as "Copy to Mac").
    private static func checkedDestination(_ relative: String, in backupsFolder: URL,
                                           protectedFolders: [URL]) throws -> URL {
        let components = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !relative.hasPrefix("/"), !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              let root = PathGuard.realPath(backupsFolder.path),
              let resolved = PathGuard.resolve(backupsFolder.appending(path: relative).path),
              PathGuard.isInside(resolved, folder: root) else {
            throw PodDataError.destinationRefused(relative)
        }
        for folder in protectedFolders {
            let protected = PathGuard.realPath(folder.path) ?? folder.standardizedFileURL.path
            if resolved == protected || PathGuard.isInside(resolved, folder: protected)
                || PathGuard.isInside(root, folder: protected) {
                throw PodDataError.destinationRefused(resolved)
            }
        }
        return URL(filePath: resolved)
    }
}
