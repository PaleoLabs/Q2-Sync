//
//  PhotoNameCache.swift
//  Q2-Sync › Core › Models
//
//  PURPOSE
//  Remembers each photo's original file name and type between reads of
//  the Photos library (issue #68). Asking PhotoKit for them
//  (`PHAssetResource.assetResources(for:)`) costs a few milliseconds per
//  photo: about 10 of the 11 seconds a 4,418-photo library took to read.
//  With this cache only photos new since the last read are asked about
//  (that library's refresh: 0.8 s instead of 12 s).
//
//  WHY BY ID ALONE
//  A photo's original file never changes: editing a photo, or making it a
//  favourite, adds or changes other resources, not the original's name or
//  type. So an entry stays right for as long as the photo exists, and the
//  modification date isn't part of the key (that would re-ask after every
//  edit for the same answer).
//
//  SAFETY
//  Only a convenience: a missing, unreadable or old-format file just means
//  every photo is asked about again. Saved in the app's own container
//  (`Application Support/Q2 Sync/Photo Names.json`), never in the Photos
//  library or on the card.
//
//  HOW IT FITS
//  `PhotoKitSource.readAssets()` loads it, fills in what's missing, drops
//  photos no longer in the library (`keepOnly`) and saves it.
//

import Foundation

/// Original file names and types of photos, by PhotoKit local identifier.
struct PhotoNameCache: Sendable, Equatable {

    /// What PhotoKit said about one photo's original file. Both may be
    /// `nil` when PhotoKit had no resource for it; that answer is kept too.
    struct Entry: Codable, Sendable, Equatable {
        var name: String?
        var type: String?
    }

    /// Bump when `Entry`'s meaning changes; an old file is then ignored.
    static let formatVersion = 1

    private(set) var entries: [String: Entry] = [:]

    init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    subscript(assetID: String) -> Entry? {
        get { entries[assetID] }
        set { entries[assetID] = newValue }
    }

    /// Forgets photos that are no longer in the library.
    mutating func keepOnly(_ assetIDs: Set<String>) {
        entries = entries.filter { assetIDs.contains($0.key) }
    }

    // MARK: - File

    private struct FileFormat: Codable {
        var version: Int
        var entries: [String: Entry]
    }

    /// `Application Support/Q2 Sync/Photo Names.json`.
    static var defaultURL: URL {
        DeviceStore.defaultDirectory.appending(path: "Photo Names.json")
    }

    /// The saved cache, or an empty one if there's none (or it can't be read).
    static func load(from url: URL = defaultURL) -> PhotoNameCache {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(FileFormat.self, from: data),
              file.version == formatVersion else { return PhotoNameCache() }
        return PhotoNameCache(entries: file.entries)
    }

    /// Saves the cache. Errors are ignored (see SAFETY).
    ///
    /// - Side effects: Writes one file in the app's own container.
    func save(to url: URL = defaultURL) {
        guard let data = try? JSONEncoder().encode(FileFormat(version: Self.formatVersion, entries: entries)) else {
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
