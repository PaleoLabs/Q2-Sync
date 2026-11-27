//
//  PathGuard.swift
//  Q2-Sync › Core › SyncEngine
//
//  PURPOSE
//  The single gatekeeper for every file write, move and delete the app
//  makes on the card. If the guard says no, nothing happens.
//
//  HOW IT FITS
//  `CardFileSystem` is the only code that changes files on the card, and
//  it calls `PathGuard.check` before EVERY change. Nothing else in the app
//  calls FileManager's write/delete methods on card paths.
//
//  WHAT IT REFUSES
//  (a) Anything not strictly inside the confirmed Q2 card's root folder,
//      after resolving symlinks and "..", so tricks like
//      "Music/../../Users/me" or a symlink on the card pointing at your Mac
//      are caught. The card root itself is never written or deleted.
//  (b) Anything on a volume that isn't the confirmed card: wrong UUID,
//      startup disk, internal fixed disk, non-removable or non-FAT.
//      Re-checked on every call, so swapping the card mid-sync is caught.
//  (c) Anything under ~/Music or the Apple Music media folder, wherever it
//      lives. (The sandbox already makes ~/Music read-only; this is a
//      second, independent lock.)
//  (d) Anything on the profile's reserved-items list (firmware files,
//      hidden folders, macOS metadata…).
//  Plus: normal sync writes and deletes may only happen inside the app's
//  own areas (Music/, .q2sync/, the playlist folder, where only `.m3u` files
//  directly inside are allowed). Deleting elsewhere
//  needs the explicit `.deleteConfirmedByUser` operation, used only for
//  card-only files the user chose to delete.
//  Four narrow exceptions to (d):
//  • `checkAppleDoubleCompanion` lets the app delete the macOS `._`
//    companion of a song it manages (see that method).
//  • `checkStrayAppleDouble` lets the end-of-sync sweep delete any other
//    `._` file in Music/ or the playlist folder, if its contents prove it's
//    macOS metadata (see that method).
//  • `checkFirmwareUpdateFile` lets the firmware installer write or delete
//    exactly one file, `update.tar` at the card root, which is where the
//    Q2's updater looks for firmware (see that method).
//  • `checkPodDataPath` lets a restore write back Q2 Pod's own data files
//    (ratings, EQ presets…), and only the paths in `PodDataBackup.items`.
//

import Foundation

/// Refuses any card operation that breaks the safety rules.
struct PathGuard: Sendable {

    /// The kinds of operation the guard can approve.
    enum Operation: String, Sendable {
        /// Create or overwrite a file (in the app's own areas only).
        case write
        /// Create a folder (in the app's own areas only).
        case createDirectory
        /// Delete or move away a file/folder (in the app's own areas only).
        case delete
        /// Delete a card-only file the user explicitly chose (anywhere on
        /// the card except reserved items).
        case deleteConfirmedByUser
    }

    /// Why an operation was refused. Every case explains itself.
    enum Violation: LocalizedError, Equatable {
        case invalidPath(String)
        case outsideCard(String)
        case cardRootItself
        case wrongVolume(String)
        case protectedFolder(String)
        case reservedItem(String)
        case outsideManagedArea(String)

        var errorDescription: String? {
            switch self {
            case .invalidPath(let path):        return "Refused an invalid path: \(path)"
            case .outsideCard(let path):        return "Refused a path outside the Q2's card: \(path)"
            case .cardRootItself:               return "Refused to change the card's top folder itself."
            case .wrongVolume(let reason):      return "Refused because the card isn't the confirmed Q2: \(reason)"
            case .protectedFolder(let path):    return "Refused a path inside your Music folder: \(path)"
            case .reservedItem(let path):       return "Refused to touch a firmware/system item: \(path)"
            case .outsideManagedArea(let path): return "Refused a change outside Q2 Sync's folders: \(path)"
            }
        }
    }

    /// The card root, fully resolved (no symlinks, no "..").
    let cardRoot: URL

    /// The UUID the user confirmed for this card.
    let expectedVolumeUUID: String

    /// Firmware profile, for reserved items and managed folder names.
    let profile: DeviceProfile

    /// Resolved folders that must never be written (~/Music, media folder).
    let protectedFolders: [String]

    /// Reads volume facts; injectable so tests can simulate volumes.
    /// `@Sendable` means the closure is safe to call from any thread.
    private let volumeInfo: @Sendable (URL) -> VolumeInfo?

    /// Top-level folders where normal sync writes are allowed (lowercased).
    private var managedAreas: Set<String> {
        [profile.musicFolderName, profile.appStateFolderName, profile.playlistFolderName]
            .reduce(into: Set<String>()) { $0.insert($1.lowercased()) }
    }

    /// Creates a guard for one card, checking the card itself first.
    ///
    /// - Parameters:
    ///   - cardRoot: The card's root (mount point) URL.
    ///   - expectedVolumeUUID: The UUID the user confirmed.
    ///   - profile: The device's firmware profile.
    ///   - extraProtectedFolders: More Mac folders to protect, e.g. the
    ///     Apple Music media folder from the library snapshot.
    ///   - homeMusicFolder: The user's ~/Music folder, always protected.
    ///     Tests pass a temp folder so they never touch the real one.
    ///   - volumeInfo: How to read volume facts (tests inject fakes).
    /// - Throws: `Violation` if the card itself fails the checks.
    init(cardRoot: URL,
         expectedVolumeUUID: String,
         profile: DeviceProfile,
         extraProtectedFolders: [URL] = [],
         homeMusicFolder: URL = PathGuard.defaultHomeMusicFolder,
         volumeInfo: @escaping @Sendable (URL) -> VolumeInfo? = VolumeInfo.read) throws {
        guard let resolvedRoot = Self.realPath(cardRoot.path) else {
            throw Violation.invalidPath(cardRoot.path)
        }
        self.cardRoot = URL(filePath: resolvedRoot, directoryHint: .isDirectory)
        self.expectedVolumeUUID = expectedVolumeUUID
        self.profile = profile
        self.volumeInfo = volumeInfo

        // Protect ~/Music (the REAL home folder, not the sandbox container)
        // and any extra folders, using resolved paths.
        let candidates = [homeMusicFolder] + extraProtectedFolders
        self.protectedFolders = candidates.compactMap { Self.realPath($0.path) ?? $0.standardizedFileURL.path }

        // The card must not itself be inside a protected folder.
        if let folder = protectedFolders.first(where: { Self.isInside(resolvedRoot, folder: $0) || resolvedRoot == $0 }) {
            throw Violation.protectedFolder(folder)
        }
        try checkVolume(at: self.cardRoot)
    }

    // MARK: - Checking

    /// Checks a card-relative path like `"Music/Adele/25/01 Hello.m4a"`.
    ///
    /// - Parameters:
    ///   - relativePath: Path relative to the card root, "/" separated.
    ///   - operation: What the caller wants to do.
    /// - Returns: The resolved, approved absolute URL to use.
    /// - Throws: `Violation` describing the first broken rule.
    func check(_ relativePath: CardPath, for operation: Operation) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        // Refuse anything odd outright instead of trying to "fix" it:
        // absolute paths, "..", ".", empty segments, backslashes.
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.contains("\\"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw Violation.invalidPath(relativePath)
        }
        return try check(url: cardRoot.appending(path: relativePath), for: operation)
    }

    /// Checks an absolute URL.
    ///
    /// - Parameters:
    ///   - url: The target file or folder.
    ///   - operation: What the caller wants to do.
    /// - Returns: The resolved, approved URL.
    /// - Throws: `Violation` describing the first broken rule.
    func check(url: URL, for operation: Operation) throws -> URL {
        // Resolve symlinks and ".." in the parts that exist on disk.
        guard let resolved = Self.resolve(url.path) else { throw Violation.invalidPath(url.path) }

        // (c) Never inside ~/Music or the media folder.
        if protectedFolders.contains(where: { Self.isInside(resolved, folder: $0) || resolved == $0 }) {
            throw Violation.protectedFolder(resolved)
        }

        // (a) Strictly inside the card root.
        let rootPath = cardRoot.path
        if resolved == rootPath { throw Violation.cardRootItself }
        guard Self.isInside(resolved, folder: rootPath) else { throw Violation.outsideCard(resolved) }

        let relative = String(resolved.dropFirst(rootPath.count + 1))
        let components = relative.split(separator: "/").map(String.init)

        // (d) Not a reserved item. One narrow exception: on firmware that
        // supports audiobooks (Q2 Pod), `Audiobooks/<book>/<audio file>`,
        // and only these operations: create `Audiobooks` or a book folder;
        // write an audio file directly inside a book folder; delete such a
        // file or an (empty) book folder. Nothing deeper, no other file
        // types, never `Audiobooks` itself, never a user-confirmed delete.
        let isAudiobookItem = profile.isAudiobookItem(components)
        if isAudiobookItem {
            let ext = (components.last.map { ($0 as NSString).pathExtension } ?? "").lowercased()
            let allowed: Bool
            switch operation {
            case .createDirectory: allowed = components.count <= 2
            case .write: allowed = components.count == 3 && CardScanner.audioExtensions.contains(ext)
            case .delete: allowed = components.count >= 2
            case .deleteConfirmedByUser: allowed = false
            }
            if !allowed || profile.reservedItems.isReservedInside(components: components) {
                throw Violation.reservedItem(relative)
            }
        } else if profile.reservedItems.isReserved(components: components) {
            throw Violation.reservedItem(relative)
        }

        // Managed areas for normal sync operations.
        if operation != .deleteConfirmedByUser {
            guard let top = components.first, managedAreas.contains(top.lowercased()) || isAudiobookItem else {
                throw Violation.outsideManagedArea(relative)
            }
            // Never delete a whole managed folder (e.g. all of Music/).
            if operation == .delete && components.count == 1 {
                throw Violation.outsideManagedArea(relative)
            }
            // The playlist folder may only hold playlist files, directly
            // inside it. This protects anything else people keep there,
            // such as Q2 Pod's playlist pictures (Road Trip.jpg).
            if top.lowercased() == profile.playlistFolderName.lowercased() {
                let ext = "." + profile.playlistFormat.fileExtension.lowercased()
                let isFolderItself = components.count == 1 && operation == .createDirectory
                let isPlaylistFile = components.count == 2 && components[1].lowercased().hasSuffix(ext)
                guard isFolderItself || isPlaylistFile else { throw Violation.outsideManagedArea(relative) }
            }
        }

        // (b) Still the confirmed, removable, FAT-family card.
        try checkVolume(at: cardRoot)

        return URL(filePath: resolved)
    }

    /// Largest file accepted as a macOS "AppleDouble" companion. Real ones
    /// hold only a few extended attributes (usually 4 KB).
    static let maximumAppleDoubleSize: UInt64 = 1 << 20 // 1 MB

    /// Approves deleting the `._<name>` companion file macOS creates next to
    /// a file on FAT/exFAT cards to store its extended attributes.
    ///
    /// WHY THIS NARROW EXCEPTION EXISTS
    /// `._` files are normally reserved (rule d). But macOS creates one for
    /// every song a sandboxed app copies to the card, and some players show
    /// `._01 Song.m4a` as a broken song. So Q2 Sync removes the companion of
    /// a song IT manages, and nothing else. Conditions, all required:
    ///  • the main file passes the normal `.delete` check (inside Music/ or
    ///    the app's folders, not reserved, on the confirmed card);
    ///  • the companion is in the same folder, named "._" + the main name;
    ///  • it's a plain file (not a symlink or folder) under 1 MB.
    ///
    /// - Parameter path: The MAIN file, e.g. `"Music/A/B/01 X.m4a"`.
    /// - Returns: The companion's URL, approved for deletion.
    /// - Throws: `Violation` if any condition fails.
    func checkAppleDoubleCompanion(of path: CardPath) throws -> URL {
        let main = try check(path, for: .delete)
        let companion = main.deletingLastPathComponent().appending(path: "._" + main.lastPathComponent)
        // `lstat` reads the entry itself without following a symlink.
        var info = stat()
        guard lstat(companion.path, &info) == 0 else { throw Violation.invalidPath(companion.path) }
        let isRegularFile = (info.st_mode & S_IFMT) == S_IFREG
        guard isRegularFile, UInt64(info.st_size) <= Self.maximumAppleDoubleSize,
              Self.resolve(companion.path) == companion.path else {
            throw Violation.reservedItem(companion.path)
        }
        return companion
    }

    /// The first four bytes of every macOS AppleDouble file.
    static let appleDoubleMagic: [UInt8] = [0x00, 0x05, 0x16, 0x07]

    /// Approves deleting a `._` file found by the end-of-sync sweep, whether
    /// or not Q2 Sync wrote the file it belongs to (or that file still exists).
    ///
    /// WHY THIS NARROW EXCEPTION EXISTS
    /// Music copied to the card in Finder gets `._` companions too, and the
    /// Q2 can list them as broken songs. `checkAppleDoubleCompanion` only
    /// covers songs Q2 Sync manages. Conditions, all required:
    ///  • the path is inside Music/ (any depth) or directly inside the
    ///    playlist folder;
    ///  • only its last part is hidden, and it starts with "._" (so nothing
    ///    inside a hidden folder, such as a firmware one, is ever touched);
    ///  • it resolves to itself (no symlink leads elsewhere), strictly inside
    ///    the card and outside the protected Mac folders;
    ///  • it's a plain file under 1 MB whose first bytes are the AppleDouble
    ///    signature, so it's macOS metadata and not a file someone named "._";
    ///  • the card is still the confirmed, eligible card.
    ///
    /// - Parameter relativePath: e.g. `"Music/A/B/._01 X.mp3"`.
    /// - Returns: The approved URL.
    /// - Throws: `Violation` if any condition fails.
    func checkStrayAppleDouble(_ relativePath: CardPath) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 2, !relativePath.hasPrefix("/"), !relativePath.contains("\\"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw Violation.invalidPath(relativePath)
        }
        let top = components[0].lowercased()
        let inMusic = top == profile.musicFolderName.lowercased()
        let inPlaylists = top == profile.playlistFolderName.lowercased() && components.count == 2
        guard inMusic || inPlaylists else { throw Violation.outsideManagedArea(relativePath) }
        guard let name = components.last, name.hasPrefix("._"), name.count > 2,
              !components.dropLast().contains(where: { $0.hasPrefix(".") }) else {
            throw Violation.reservedItem(relativePath)
        }

        let url = cardRoot.appending(path: relativePath)
        guard let resolved = Self.resolve(url.path), resolved == url.path else {
            throw Violation.invalidPath(relativePath)
        }
        if protectedFolders.contains(where: { Self.isInside(resolved, folder: $0) || resolved == $0 }) {
            throw Violation.protectedFolder(resolved)
        }
        guard Self.isInside(resolved, folder: cardRoot.path) else { throw Violation.outsideCard(resolved) }

        var info = stat()
        guard lstat(resolved, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              UInt64(info.st_size) <= Self.maximumAppleDoubleSize,
              Self.startsWithAppleDoubleMagic(resolved) else {
            throw Violation.reservedItem(relativePath)
        }
        try checkVolume(at: cardRoot)
        return URL(filePath: resolved)
    }

    /// `true` if the file's first bytes are the AppleDouble signature.
    static func startsWithAppleDoubleMagic(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: appleDoubleMagic.count)) ?? Data()
        return Array(head) == appleDoubleMagic
    }

    /// Approves writing or deleting the firmware file `update.tar` at the
    /// card root, and nothing else.
    ///
    /// WHY THIS NARROW EXCEPTION EXISTS
    /// `update.tar` is reserved (rule d) so syncing never touches it. But
    /// the firmware installer's whole job is to put one there, when the user
    /// asks, after the file was checked (`FirmwareImage`). Conditions, all
    /// required:
    ///  • the path is exactly `<card root>/update.tar` (any letter case,
    ///    as FAT/exFAT ignore case);
    ///  • whatever is there now is a plain file (not a folder or symlink),
    ///    or nothing;
    ///  • the card is still the confirmed, eligible card.
    /// The `.part` file Q2 Pod's own Network update writes is NOT covered.
    ///
    /// - Parameter operation: `.write` or `.delete`.
    /// - Returns: The approved URL.
    /// - Throws: `Violation` if any condition fails.
    func checkFirmwareUpdateFile(for operation: Operation) throws -> URL {
        guard operation == .write || operation == .delete else { throw Violation.reservedItem(FirmwareImage.fileName) }
        let url = cardRoot.appending(path: FirmwareImage.fileName)
        guard let resolved = Self.resolve(url.path),
              (resolved as NSString).deletingLastPathComponent == cardRoot.path,
              (resolved as NSString).lastPathComponent.lowercased() == FirmwareImage.fileName else {
            throw Violation.reservedItem(FirmwareImage.fileName)
        }
        if protectedFolders.contains(where: { Self.isInside(resolved, folder: $0) }) {
            throw Violation.protectedFolder(resolved)
        }
        var info = stat()
        if lstat(resolved, &info) == 0, (info.st_mode & S_IFMT) != S_IFREG {
            throw Violation.reservedItem(FirmwareImage.fileName)
        }
        try checkVolume(at: cardRoot)
        return URL(filePath: resolved)
    }

    /// Approves deleting `._update.tar`, the macOS companion of the
    /// firmware file, under the same rules as `checkAppleDoubleCompanion`.
    func checkFirmwareUpdateCompanion() throws -> URL {
        let main = try checkFirmwareUpdateFile(for: .delete)
        let companion = main.deletingLastPathComponent().appending(path: "._" + main.lastPathComponent)
        var info = stat()
        guard lstat(companion.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              UInt64(info.st_size) <= Self.maximumAppleDoubleSize else {
            throw Violation.reservedItem(companion.lastPathComponent)
        }
        return companion
    }

    /// Approves restoring one of Q2 Pod's data files from a backup, or
    /// creating the folders they go in.
    ///
    /// WHY THIS NARROW EXCEPTION EXISTS
    /// Q2 Pod's data (`.ratings.tsv`, `EQ/`, …) sits in reserved places
    /// that syncing never touches. Restoring a backup the user chose must
    /// write exactly there. Conditions, all required:
    ///  • the path is one of `PodDataBackup.items`, inside one of its
    ///    folders, or (to create folders only) a parent folder of one;
    ///  • it has no `..`, `.` or empty parts, and resolves to itself (no
    ///    symlink leads elsewhere);
    ///  • what's there now is a plain file (to write) or a folder (to
    ///    create), or nothing;
    ///  • the card is still the confirmed, eligible card.
    ///
    /// - Parameters:
    ///   - relativePath: e.g. `".ratings.tsv"` or `"EQ/Bass.txt"`.
    ///   - operation: `.write` or `.createDirectory`.
    /// - Returns: The approved URL.
    /// - Throws: `Violation` if any condition fails.
    func checkPodDataPath(_ relativePath: CardPath, for operation: Operation) throws -> URL {
        guard operation == .write || operation == .createDirectory else { throw Violation.reservedItem(relativePath) }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.contains("\\"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw Violation.invalidPath(relativePath)
        }
        let lower = relativePath.lowercased()
        let allowed = PodDataBackup.items.contains { item in
            let itemPath = item.path.lowercased()
            if PodDataBackup.belongs(relativePath, to: item) {
                // Files go at the item or inside its folder; folders only
                // for a folder item (itself or below).
                return operation == .write ? !(item.isFolder && lower == itemPath) : item.isFolder
            }
            return operation == .createDirectory && itemPath.hasPrefix(lower + "/")
        }
        guard allowed else { throw Violation.reservedItem(relativePath) }

        let target = cardRoot.appending(path: relativePath).path
        guard let resolved = Self.resolve(target), resolved.lowercased() == target.lowercased() else {
            throw Violation.reservedItem(relativePath)
        }
        if protectedFolders.contains(where: { Self.isInside(resolved, folder: $0) }) {
            throw Violation.protectedFolder(resolved)
        }
        var info = stat()
        if lstat(resolved, &info) == 0 {
            let type = info.st_mode & S_IFMT
            if type != (operation == .write ? S_IFREG : S_IFDIR) { throw Violation.reservedItem(relativePath) }
        }
        try checkVolume(at: cardRoot)
        return URL(filePath: resolved)
    }

    /// Confirms the volume at `url` is the expected, eligible card.
    private func checkVolume(at url: URL) throws {
        guard let info = volumeInfo(url) else { throw Violation.wrongVolume("its details can't be read") }
        guard info.uuid == expectedVolumeUUID else { throw Violation.wrongVolume("a different card is mounted") }
        if let problem = VolumeEligibility.problem(with: info) {
            throw Violation.wrongVolume(problem.explanation)
        }
    }

    // MARK: - Path helpers

    /// `true` if `path` is strictly inside `folder` (component-wise, so
    /// "/Volumes/Q2CARD2" is NOT inside "/Volumes/Q2CARD").
    static func isInside(_ path: String, folder: String) -> Bool {
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        return path.hasPrefix(prefix)
    }

    /// Resolves a path that may not exist yet: the longest existing prefix
    /// is resolved with `realpath` (following symlinks), then the rest is
    /// appended. A remaining ".." can't be resolved safely, so it fails.
    static func resolve(_ path: String) -> String? {
        var existing = (path as NSString).standardizingPath
        var tail: [String] = []
        while !existing.isEmpty, existing != "/" {
            if let real = realPath(existing) {
                let parts = [real] + tail.reversed()
                let joined = parts.joined(separator: "/")
                return joined.contains("/../") || joined.hasSuffix("/..") ? nil : joined
            }
            tail.append((existing as NSString).lastPathComponent)
            existing = (existing as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// The C library's `realpath`: an absolute path with every symlink,
    /// "." and ".." resolved, or `nil` if the path doesn't exist.
    static func realPath(_ path: String) -> String? {
        guard let pointer = Darwin.realpath(path, nil) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    /// The real ~/Music folder (outside the sandbox container).
    static var defaultHomeMusicFolder: URL {
        realHomeDirectory.appending(path: "Music", directoryHint: .isDirectory)
    }

    /// The user's real home folder (e.g. /Users/you). Inside the sandbox,
    /// `FileManager.homeDirectoryForCurrentUser` points to the app's
    /// container instead, so we ask the system user database.
    static var realHomeDirectory: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(filePath: String(cString: dir), directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
