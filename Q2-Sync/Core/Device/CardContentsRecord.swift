//
//  CardContentsRecord.swift
//  Q2-Sync › Core › Device
//
//  PURPOSE
//  A small Mac-side note of which songs and audiobooks Q2 Sync has put on
//  each Q2's card, so the library and Books browsers can mark "On Q2" while
//  the Q2 is unplugged.
//
//  HOW IT FITS
//  The card's own manifest (`.q2sync/manifest.json`) stays the source of
//  truth and is what syncing uses. Whenever `DeviceMonitor` reads that
//  manifest (on connect and after a sync), it saves this record from it.
//  The browser only ever reads the record, and says "as of" its date.
//  Nothing here is used for planning, copying or deleting.
//
//  WHERE IT LIVES
//  `Application Support/Q2 Sync/Card Contents/<volume UUID>.json` inside
//  the app's sandbox container: app data, not a user document, so not in
//  Downloads or Documents. It holds song and book IDs only (no titles or
//  paths).
//  Forgetting a Q2 deletes its record.
//

import Foundation

/// Which songs were on one Q2's card when Q2 Sync last looked.
struct CardContentsRecord: Codable, Sendable, Equatable {

    /// The card's volume UUID (which Q2 this is about).
    var volumeUUID: String

    /// When the card's manifest was last written, i.e. the last sync.
    /// `nil` if the card had never been synced.
    var lastSynced: Date?

    /// When Q2 Sync last read the card (connected or synced).
    var checkedAt: Date

    /// Apple Music persistent IDs of the songs Q2 Sync manages on the card.
    var trackIDs: Set<PersistentID>

    /// Apple Books ids of the audiobooks Q2 Sync manages on the card.
    /// `nil` in records saved before audiobooks were recorded: unknown
    /// until the Q2 is next read.
    var audiobookIDs: Set<String>?

    /// Builds a record from the card's manifest.
    ///
    /// - Parameters:
    ///   - volumeUUID: Which card.
    ///   - manifest: The manifest just read from it.
    ///   - checkedAt: When it was read (defaults to now).
    init(volumeUUID: String, manifest: SyncManifest, checkedAt: Date = .now) {
        self.volumeUUID = volumeUUID
        self.lastSynced = manifest.updatedAt
        self.checkedAt = checkedAt
        self.trackIDs = Set(manifest.entries.keys)
        self.audiobookIDs = manifest.audiobooks.map { Set($0.keys) } ?? []
    }
}

/// Saves and loads `CardContentsRecord`s, one small file per Q2.
///
/// Every failure is quiet: the record is only a convenience, so a missing
/// or unreadable file just means "no marks to show".
struct CardContentsStore: Sendable {

    /// The folder holding the records.
    let directory: URL

    /// `Application Support/Q2 Sync/Card Contents` (inside the sandbox
    /// container), next to the device store's `devices.json`.
    static var defaultDirectory: URL {
        DeviceStore.defaultDirectory.appending(path: "Card Contents", directoryHint: .isDirectory)
    }

    /// Creates a store.
    ///
    /// - Parameter directory: Where to keep records. Tests pass a temp folder.
    init(directory: URL = CardContentsStore.defaultDirectory) {
        self.directory = directory
    }

    /// The record for one Q2, if there is one.
    func load(volumeUUID: String) -> CardContentsRecord? {
        guard let url = fileURL(for: volumeUUID), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CardContentsRecord.self, from: data)
    }

    /// Saves (replaces) a record. Errors are ignored; see the type comment.
    ///
    /// - Side effects: Writes one file in the app's own container.
    func save(_ record: CardContentsRecord) {
        guard let url = fileURL(for: record.volumeUUID) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(record) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Deletes a Q2's record (when the Q2 is forgotten).
    func remove(volumeUUID: String) {
        guard let url = fileURL(for: volumeUUID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// The file for a UUID, or `nil` if the UUID has characters a volume
    /// UUID never has (so it can't name a path outside the folder).
    private func fileURL(for volumeUUID: String) -> URL? {
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF-")
        guard !volumeUUID.isEmpty, volumeUUID.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return directory.appending(path: "\(volumeUUID).json")
    }
}
