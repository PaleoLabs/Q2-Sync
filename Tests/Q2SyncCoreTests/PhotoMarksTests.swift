//
//  PhotoMarksTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Tests for the Albums browser's marks (on Q2 / next sync / not chosen),
//  the photo IDs in the Mac-side card record they come from, and when the
//  sidebar's Photos section shows (#68).
//
//  SAFETY
//  In-memory values and temp folders only.
//

import Foundation
import Testing
@testable import Q2SyncCore

@Suite("Photo marks")
struct PhotoMarksTests {

    func photo(_ id: String, favorite: Bool = false) -> PhotoAsset {
        PhotoAsset(id: id, created: Date(timeIntervalSince1970: 1_700_000_000), modified: nil,
                   isFavorite: favorite, isHidden: false, pixelWidth: 400, pixelHeight: 300,
                   originalFileName: "IMG_\(id).JPG", uniformTypeIdentifier: "public.jpeg")
    }

    /// A library with album "trip" (a, b) and "pets" (c), and a loose photo d.
    var library: PhotoLibraryContents {
        PhotoLibraryContents(
            assets: [photo("a", favorite: true), photo("b"), photo("c"), photo("d")],
            albums: [PhotoAlbum(id: "trip", title: "Trip", kind: .user, folderPath: [], assetIDs: ["a", "b"]),
                     PhotoAlbum(id: "pets", title: "Pets", kind: .user, folderPath: [], assetIDs: ["c"])])
    }

    /// A card record with these (asset, album) copies on it.
    func record(_ copies: [(String, String?)]) -> CardContentsRecord {
        var manifest = SyncManifest()
        manifest.photos = Dictionary(uniqueKeysWithValues: copies.map { asset, album in
            (PhotoPlanner.key(assetID: asset, albumID: album),
             PhotoRecord(path: "Photos/\(album ?? "")/\(asset).jpg", assetID: asset, albumID: album,
                         albumTitle: album, modified: nil, fullResolution: false, cardSize: 1, syncedAt: .now))
        })
        return CardContentsRecord(volumeUUID: "ABCD-1234", manifest: manifest)
    }

    func device(_ uuid: String, photos: Bool?) -> KnownDevice {
        var device = KnownDevice(volumeUUID: uuid, name: "Q2", firmware: .q2Pod, bookmarkData: Data(),
                                 addedDate: .now, hasCompletedFirstSync: false)
        device.photos = photos.map { PhotoSelection(isEnabled: $0) }
        return device
    }

    @Test("The card record keeps each photo's id once, even when it's in two albums")
    func recordKeepsAssetIDs() {
        #expect(record([("a", "trip"), ("a", "pets"), ("d", nil)]).photoAssetIDs == ["a", "d"])
        // A manifest from before photos: known to have none.
        #expect(CardContentsRecord(volumeUUID: "ABCD", manifest: SyncManifest()).photoAssetIDs == [])
    }

    @Test("A record saved before photos were recorded still loads, with no photos known")
    func oldRecordLoads() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = #"{"audiobookIDs":[],"checkedAt":"2026-11-20T10:00:00Z","podcastEpisodeIDs":[],"trackIDs":["A1"],"volumeUUID":"ABCD"}"#
        try Data(old.utf8).write(to: folder.appending(path: "ABCD.json"))

        let loaded = try #require(CardContentsStore(directory: folder).load(volumeUUID: "ABCD"))
        #expect(loaded.photoAssetIDs == nil)
        let marks = PhotoMarks(record: loaded, selection: PhotoSelection(isEnabled: true), library: library)
        #expect(!marks.hasQ2)
        #expect(marks.placement(of: photo("a")) == nil)
    }

    @Test("Without a Q2, nothing is marked")
    func noQ2() {
        let marks = PhotoMarks(record: nil, selection: nil, library: library)
        #expect(!marks.hasQ2)
        #expect(marks.placement(of: photo("a")) == nil)
        #expect(marks.onQ2Count(of: library.assets) == nil)
    }

    @Test("On Q2, next sync and not chosen follow the record and the Q2's settings")
    func placements() {
        let selection = PhotoSelection(isEnabled: true, includesAll: false, albumIDs: ["trip"])
        let marks = PhotoMarks(record: record([("a", "trip"), ("c", "pets")]), selection: selection,
                               library: library)
        #expect(marks.hasQ2)
        #expect(marks.placement(of: photo("a")) == .onQ2)
        // On the Q2 but no longer chosen: still on it until the next sync.
        #expect(marks.placement(of: photo("c")) == .onQ2)
        #expect(marks.placement(of: photo("b")) == .nextSync)
        #expect(marks.placement(of: photo("d")) == .notChosen)
        #expect(marks.onQ2Count(of: library.assets) == 2)
    }

    @Test("All photos and albums brings loose photos too; Only favorites narrows it")
    func allAndFavorites() {
        let all = PhotoMarks(record: record([]), selection: PhotoSelection(isEnabled: true), library: library)
        #expect(library.assets.allSatisfy { all.placement(of: $0) == .nextSync })

        let favorites = PhotoMarks(record: record([]),
                                   selection: PhotoSelection(isEnabled: true, onlyFavorites: true),
                                   library: library)
        #expect(favorites.placement(of: photo("a")) == .nextSync)
        #expect(favorites.placement(of: photo("b")) == .notChosen)
    }

    @Test("With photos off, or a folder source, nothing is copied at the next sync")
    func offOrFolder() {
        let off = PhotoMarks(record: record([]), selection: PhotoSelection(isEnabled: false), library: library)
        #expect(off.placement(of: photo("a")) == .notChosen)
        let folder = PhotoMarks(record: record([]),
                                selection: PhotoSelection(isEnabled: true, source: .folder(bookmark: Data())),
                                library: library)
        #expect(folder.placement(of: photo("a")) == .notChosen)
    }

    @Test("The Photos section shows when any known Q2 syncs photos")
    func sectionShowsForAnyQ2() {
        #expect(![KnownDevice]().anySyncsPhotos)
        #expect(![device("A", photos: nil), device("B", photos: false)].anySyncsPhotos)
        #expect([device("A", photos: false), device("B", photos: true)].anySyncsPhotos)
    }
}
