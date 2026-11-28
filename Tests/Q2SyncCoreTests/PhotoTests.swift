//
//  PhotoTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Tests for photos (issue #68): the Photos tab's settings, saving them
//  per Q2, the path guard's `Photos/` exception, planning, making the
//  JPEGs, writing and removing them, and the capacity and safety checks.
//
//  SAFETY
//  Uses temporary folders only; never the real Photos library or a real
//  card.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Q2SyncCore

// MARK: - Helpers

private func write(_ card: TestCard, _ path: String, bytes: Int = 1) throws {
    let url = card.root.appending(path: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 1, count: bytes).write(to: url)
}

private func album(_ id: String, _ kind: PhotoAlbumKind = .user) -> PhotoAlbum {
    PhotoAlbum(id: id, title: id, kind: kind, folderPath: [], assetIDs: [])
}

// MARK: - Settings

@Suite("Photos: settings")
struct PhotoSelectionTests {

    @Test("Off, or Selected with no ticks and no recent period, chooses nothing")
    func choosesNothing() {
        #expect(PhotoSelection().choosesNothing)
        #expect(!PhotoSelection(isEnabled: true).choosesNothing)
        #expect(PhotoSelection(isEnabled: true, includesAll: false).choosesNothing)
        #expect(!PhotoSelection(isEnabled: true, includesAll: false, albumIDs: ["a"]).choosesNothing)
        #expect(!PhotoSelection(isEnabled: true, includesAll: false, recentWindow: .lastMonth).choosesNothing)
    }

    @Test("All ticks user albums only; Selected ticks what was chosen and keeps it across All")
    func ticks() {
        var s = PhotoSelection(isEnabled: true)
        #expect(s.isTicked(album("trip")))
        #expect(!s.isTicked(album("fav", .favorites)))
        #expect(!s.isTicked(album("hidden", .hidden)))
        #expect(!s.isTicked(album("recent", .recentlyAdded)))
        #expect(!s.isTicked(album("selfies", .mediaType)))

        s.setTicked(true, ids: ["trip"])
        #expect(s.albumIDs.isEmpty) // ignored under All
        s.includesAll = false
        s.setTicked(true, ids: ["trip", "hidden"])
        #expect(s.isTicked(album("hidden", .hidden)))
        s.setTicked(false, ids: ["trip"])
        s.includesAll = true
        s.includesAll = false
        #expect(s.albumIDs == ["hidden"])
    }

    @Test("The recent period only applies under Selected albums")
    func recentWindow() {
        var s = PhotoSelection(isEnabled: true, recentWindow: .lastWeek)
        #expect(s.effectiveRecentWindow == nil)
        s.includesAll = false
        #expect(s.effectiveRecentWindow == .lastWeek)
    }

    @Test("Recent periods count back from now in the calendar")
    func startDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = try Date("2026-11-28T12:00:00Z", strategy: .iso8601)
        let expected: [PhotoRecentWindow: String] = [
            .lastWeek: "2026-11-21T12:00:00Z", .lastMonth: "2026-10-28T12:00:00Z",
            .last2Months: "2026-09-28T12:00:00Z", .last3Months: "2026-08-28T12:00:00Z",
            .last6Months: "2026-05-28T12:00:00Z", .lastYear: "2025-11-28T12:00:00Z",
        ]
        for window in PhotoRecentWindow.allCases {
            let start = window.startDate(before: now, calendar: calendar)
            #expect(start == (try Date(try #require(expected[window]), strategy: .iso8601)))
        }
    }

    @Test("Settings round-trip, and old or partial ones decode with defaults")
    func decoding() throws {
        let full = PhotoSelection(isEnabled: true, source: .folder(bookmark: Data([1, 2, 3])), includesAll: false,
                                  albumIDs: ["a"], onlyFavorites: true, recentWindow: .last3Months,
                                  fullResolution: true)
        let data = try JSONEncoder().encode(full)
        #expect(try JSONDecoder().decode(PhotoSelection.self, from: data) == full)

        let partial = try JSONDecoder().decode(PhotoSelection.self, from: Data(#"{"isEnabled":true}"#.utf8))
        #expect(partial == PhotoSelection(isEnabled: true))

        // A source or period a later version added doesn't lose the rest.
        let later = try JSONDecoder().decode(PhotoSelection.self, from: Data(
            #"{"isEnabled":true,"source":{"cloud":{}},"recentWindow":"last5Years","onlyFavorites":true}"#.utf8))
        #expect(later == PhotoSelection(isEnabled: true, onlyFavorites: true))
    }

    @Test("Photo settings are part of a Q2's settings and saved per Q2")
    func deviceSettings() throws {
        var settings = DeviceSyncSettings(music: SyncSelection())
        #expect(settings.photos == PhotoSelection())
        settings.photos = PhotoSelection(isEnabled: true)
        #expect(!settings.choosesNothing)

        var device = KnownDevice(volumeUUID: "U", name: "Q2", firmware: .q2Pod, bookmarkData: Data(),
                                 addedDate: .now, hasCompletedFirstSync: true)
        #expect(device.effectivePhotos == PhotoSelection())
        device.photos = PhotoSelection(isEnabled: true, onlyFavorites: true)
        #expect(device.syncSettings.photos == device.photos)

        // devices.json saved before photos existed still loads.
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(device)) as? [String: Any] ?? [:]
        old["photos"] = nil
        let decoded = try JSONDecoder().decode(KnownDevice.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(decoded.photos == nil && decoded.effectivePhotos == PhotoSelection())
    }
}

// MARK: - Path guard

@Suite("Photos on the card: path guard")
struct PhotoGuardTests {

    @Test("Q2 Pod: album folders, and photos loose in Photos or directly in an album, are allowed")
    func allowed() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let g = card.pathGuard
        _ = try g.check("Photos", for: .createDirectory)
        _ = try g.check("Photos/Iceland", for: .createDirectory)
        _ = try g.check("Photos/2024-07-01 IMG_1234.jpg", for: .write)
        _ = try g.check("Photos/Iceland/2024-07-01 IMG_1234.jpg", for: .write)
        _ = try g.check("Photos/Iceland/Map.PNG", for: .write)
        _ = try g.check("Photos/Iceland/Old.jpeg", for: .write)
        _ = try g.check("Photos/2024-07-01 IMG_1234.jpg", for: .delete)
        _ = try g.check("Photos/Iceland/2024-07-01 IMG_1234.jpg", for: .delete)
        _ = try g.check("Photos/Iceland", for: .delete)
    }

    @Test("Anything else in Photos is refused", arguments: [
        ("Photos/Album/Sub/Photo.jpg", PathGuard.Operation.write),
        ("Photos/Album/Sub", .createDirectory),
        ("Photos/Album/IMG_1.heic", .write),
        ("Photos/Album/clip.mov", .write),
        ("Photos/notes.txt", .write),
        ("Photos/Album/.hidden.jpg", .write),
        ("Photos/.photos", .createDirectory),
        ("Photos/Album/notes.txt", .delete),
        ("Photos", .delete),
        ("Photos/Album/Photo.jpg", .deleteConfirmedByUser),
        ("Photos/Photo.jpg", .deleteConfirmedByUser),
    ])
    func refused(path: String, operation: PathGuard.Operation) throws {
        let card = try TestCard(); defer { card.cleanUp() }
        #expect(throws: PathGuard.Violation.self) { try card.pathGuard.check(path, for: operation) }
    }

    @Test("Loose files that aren't photos can't be deleted; a loose photo or an album folder can")
    func looseFiles() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try write(card, "Photos/readme.txt")
        try write(card, "Photos/Loose.jpg")
        try write(card, "Photos/Album/Inside.jpg")
        try FileManager.default.createDirectory(at: card.root.appending(path: "Photos/Album/Folder.jpg"),
                                                withIntermediateDirectories: true)
        #expect(throws: PathGuard.Violation.self) { try card.pathGuard.check("Photos/readme.txt", for: .delete) }
        // A folder named like a photo inside an album was never Q2 Sync's.
        #expect(throws: PathGuard.Violation.self) {
            try card.pathGuard.check("Photos/Album/Folder.jpg", for: .delete)
        }
        _ = try card.pathGuard.check("Photos/Loose.jpg", for: .delete)
        _ = try card.pathGuard.check("Photos/Album", for: .delete)
        // Folders only go when empty: removeFile refuses the album folder.
        #expect(throws: (any Error).self) { try card.fileSystem.removeFile("Photos/Album") }
        try card.fileSystem.removeFile("Photos/Album/Inside.jpg")
        #expect(!FileManager.default.fileExists(atPath: card.root.appending(path: "Photos/Album/Inside.jpg").path))
    }

    @Test("A small photo can be written atomically, and its ._ companion removed")
    func writeAndCompanion() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try card.fileSystem.writeAtomically(Data([0xFF, 0xD8, 0xFF]), to: "Photos/Album/A.jpg")
        #expect(FileManager.default.fileExists(atPath: card.root.appending(path: "Photos/Album/A.jpg").path))
        try write(card, "Photos/Album/._A.jpg", bytes: 4_096)
        #expect(card.fileSystem.removeAppleDoubleCompanion(of: "Photos/Album/A.jpg") == .removed)
    }

    @Test("Stock firmware: Photos stays off limits")
    func stock() throws {
        let root = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let g = try PathGuard(cardRoot: root, expectedVolumeUUID: TestCard.uuid, profile: .stock,
                              homeMusicFolder: fakeHomeMusic,
                              volumeInfo: { _ in makeVolume(uuid: TestCard.uuid) })
        #expect(throws: PathGuard.Violation.self) { try g.check("Photos/Album/A.jpg", for: .write) }
        #expect(throws: PathGuard.Violation.self) { try g.check("Photos/A.jpg", for: .write) }
    }

    @Test("Scanning the card leaves Photos out of music")
    func cardScan() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try write(card, "Photos/Album/A.jpg", bytes: 4)
        #expect(CardScanner.scan(folder: "", on: card.fileSystem).isEmpty)
    }
}

// MARK: - Planning

/// 2024-07-01 12:00 UTC.
private let july1 = Date(timeIntervalSince1970: 1_719_835_200)

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return c
}()

private func photo(_ id: String, day: Int = 0, name: String? = nil, favorite: Bool = false,
                   hidden: Bool = false, modified: Date? = nil, size: (Int, Int) = (4_000, 3_000)) -> PhotoAsset {
    PhotoAsset(id: id, created: july1.addingTimeInterval(Double(day) * 86_400), modified: modified,
               isFavorite: favorite, isHidden: hidden, pixelWidth: size.0, pixelHeight: size.1,
               originalFileName: name ?? "IMG_\(id).HEIC", uniformTypeIdentifier: "public.heic")
}

private func photoAlbum(_ id: String, _ title: String, _ kind: PhotoAlbumKind = .user,
                        _ assets: [String]) -> PhotoAlbum {
    PhotoAlbum(id: id, title: title, kind: kind, folderPath: [], assetIDs: assets)
}

private func record(_ path: String, asset: String, album: String? = nil, title: String? = nil,
                    size: UInt64 = 1, modified: Date? = nil, fullResolution: Bool = false) -> PhotoRecord {
    PhotoRecord(path: path, assetID: asset, albumID: album, albumTitle: title, modified: modified,
                fullResolution: fullResolution, cardSize: size, syncedAt: july1)
}

private func manifest(_ records: [PhotoRecord]) -> SyncManifest {
    var m = SyncManifest()
    m.photos = Dictionary(records.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    return m
}

private func plan(_ library: PhotoLibraryContents, _ selection: PhotoSelection, card: TestCard,
                  manifest: SyncManifest = SyncManifest(), now: Date = july1) -> PhotoPlan {
    PhotoPlanner.plan(library: library, selection: selection, manifest: manifest,
                      card: CardFolderListing.scan(folderName: "Photos", on: card.fileSystem, includeLooseFiles: true),
                      folderName: "Photos", now: now, calendar: utc)
}

/// A small library: two trips sharing a photo, a loose one, a hidden one,
/// a favourite, and the smart albums.
private let library = PhotoLibraryContents(
    assets: [photo("1"), photo("2", day: 1, favorite: true), photo("3", day: 2), photo("4", day: 3),
             photo("5", day: 4, hidden: true)],
    albums: [
        photoAlbum("fav", "Favorites", .favorites, ["2"]),
        photoAlbum("recent", "Recently Added", .recentlyAdded, ["3", "4"]),
        photoAlbum("hidden", "Hidden", .hidden, ["5"]),
        photoAlbum("ice", "Iceland", .user, ["1", "2"]),
        photoAlbum("nor", "Norway", .user, ["2", "3", "5"]),
    ])

@Suite("Photos on the card: planning")
struct PhotoPlannerTests {

    @Test("All: each user album is a folder, photos in no album are loose, hidden and smart albums stay off")
    func all() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let p = plan(library, PhotoSelection(isEnabled: true), card: card)
        #expect(Set(p.copies.map(\.destination)) == [
            "Photos/Iceland/2024-07-01 IMG_1.jpg", "Photos/Iceland/2024-07-02 IMG_2.jpg",
            "Photos/Norway/2024-07-02 IMG_2.jpg", "Photos/Norway/2024-07-03 IMG_3.jpg",
            "Photos/2024-07-04 IMG_4.jpg",
        ])
        #expect(p.photosToAdd == 5 && p.photosToUpdate == 0)
        #expect(p.bytesToCopy == 5 * PhotoPlanner.screenCopySize)
        #expect(p.overLimit.isEmpty && p.tooManyAlbums == nil && p.note == nil)
    }

    @Test("Only favorites applies in every folder")
    func favorites() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let p = plan(library, PhotoSelection(isEnabled: true, onlyFavorites: true), card: card)
        #expect(Set(p.copies.map(\.destination)) == ["Photos/Iceland/2024-07-02 IMG_2.jpg",
                                                      "Photos/Norway/2024-07-02 IMG_2.jpg"])
    }

    @Test("Selected: only ticked albums, Hidden brings hidden photos, recent photos go loose unless an album brings them")
    func selected() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let s = PhotoSelection(isEnabled: true, includesAll: false, albumIDs: ["nor", "hidden"],
                               recentWindow: .lastWeek)
        let p = plan(library, s, card: card, now: july1.addingTimeInterval(5 * 86_400))
        #expect(Set(p.copies.map(\.destination)) == [
            "Photos/Norway/2024-07-02 IMG_2.jpg", "Photos/Norway/2024-07-03 IMG_3.jpg",
            "Photos/Hidden/2024-07-05 IMG_5.jpg",
            "Photos/2024-07-01 IMG_1.jpg", "Photos/2024-07-04 IMG_4.jpg",
        ])
        // Too long ago for "the last week": only the ticked albums.
        let later = plan(library, s, card: card, now: july1.addingTimeInterval(30 * 86_400))
        #expect(later.copies.count == 3)
    }

    @Test("Smart albums can be ticked, and become folders")
    func smartAlbums() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let p = plan(library, PhotoSelection(isEnabled: true, includesAll: false, albumIDs: ["fav"]), card: card)
        #expect(p.copies.map(\.destination) == ["Photos/Favorites/2024-07-02 IMG_2.jpg"])
    }

    @Test("Someone else's files are never overwritten; same-named albums and photos get (2)")
    func clashes() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try write(card, "Photos/Iceland/2024-07-01 IMG_1.jpg")
        let lib = PhotoLibraryContents(
            assets: [photo("1"), photo("2", name: "IMG_1.JPG")],
            albums: [photoAlbum("a", "Iceland", .user, ["1", "2"]), photoAlbum("b", "Iceland", .user, ["1"])])
        let p = plan(lib, PhotoSelection(isEnabled: true), card: card)
        #expect(Set(p.copies.map(\.destination)) == [
            "Photos/Iceland/2024-07-01 IMG_1 (2).jpg", "Photos/Iceland/2024-07-01 IMG_1 (3).jpg",
            "Photos/Iceland (2)/2024-07-01 IMG_1.jpg",
        ])
        #expect(p.removals.isEmpty)
    }

    @Test("Recorded photos stay put, and are redone when edited, missing, changed or the resolution changes")
    func updates() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try write(card, "Photos/Old Name/a.jpg", bytes: 5)
        try write(card, "Photos/Old Name/b.jpg", bytes: 5)
        try write(card, "Photos/Old Name/c.jpg", bytes: 9)
        let lib = PhotoLibraryContents(
            assets: [photo("a"), photo("b", modified: july1.addingTimeInterval(60)), photo("c"), photo("d")],
            albums: [photoAlbum("al", "New Name", .user, ["a", "b", "c", "d"])])
        let m = manifest([
            record("Photos/Old Name/a.jpg", asset: "a", album: "al", size: 5),
            record("Photos/Old Name/b.jpg", asset: "b", album: "al", size: 5, modified: july1),
            record("Photos/Old Name/c.jpg", asset: "c", album: "al", size: 5),
            record("Photos/Old Name/d.jpg", asset: "d", album: "al", size: 5),
        ])
        let p = plan(lib, PhotoSelection(isEnabled: true), card: card, manifest: m)
        #expect(p.unchangedPhotos == 1)
        #expect(p.copies.map(\.destination) == ["Photos/Old Name/b.jpg", "Photos/Old Name/c.jpg", "Photos/Old Name/d.jpg"])
        #expect(p.copies.allSatisfy { $0.kind == .update })

        let full = plan(lib, PhotoSelection(isEnabled: true, fullResolution: true), card: card, manifest: m)
        #expect(full.unchangedPhotos == 0 && full.copies.count == 4)
        #expect(full.copies.allSatisfy { $0.estimatedSize == 4_000_000 && $0.fullResolution })
    }

    @Test("Photos no longer wanted are removed, each with its reason; missing ones are forgotten")
    func removals() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let paths = ["Photos/Iceland/1.jpg", "Photos/Iceland/gone.jpg", "Photos/Norway/3.jpg",
                     "Photos/Old/1.jpg", "Photos/4.jpg", "Photos/Iceland/x.jpg"]
        for path in paths { try write(card, path) }
        try write(card, "Photos/Mine.jpg") // someone else's
        let lib = PhotoLibraryContents(
            assets: [photo("1"), photo("2", favorite: true), photo("3"), photo("4", day: -30)],
            albums: [photoAlbum("ice", "Iceland", .user, ["1", "2"]), photoAlbum("nor", "Norway", .user, ["3"])])
        let m = manifest([
            record("Photos/Iceland/1.jpg", asset: "1", album: "ice"),
            record("Photos/Iceland/gone.jpg", asset: "gone", album: "ice"),
            record("Photos/Norway/3.jpg", asset: "3", album: "nor"),
            record("Photos/Old/1.jpg", asset: "1", album: "deleted-album"),
            record("Photos/4.jpg", asset: "4"),
            record("Photos/Iceland/2.jpg", asset: "2", album: "ice"), // file gone from the card
        ])
        let s = PhotoSelection(isEnabled: true, includesAll: false, albumIDs: ["ice"], onlyFavorites: true,
                               recentWindow: .lastWeek)
        let p = plan(lib, s, card: card, manifest: m)
        let reasons = Dictionary(uniqueKeysWithValues: p.removals.map { ($0.path, $0.reason) })
        #expect(reasons == [
            "Photos/Iceland/1.jpg": .notFavorite, "Photos/Iceland/gone.jpg": .notInLibrary,
            "Photos/Norway/3.jpg": .notFavorite, "Photos/Old/1.jpg": .notFavorite, "Photos/4.jpg": .notFavorite,
        ])
        #expect(p.forgotten.isEmpty) // 2 is still wanted: it's copied again
        #expect(p.copies.map(\.destination) == ["Photos/Iceland/2.jpg"])

        let noFavorites = PhotoSelection(isEnabled: true, includesAll: false, albumIDs: ["ice"], recentWindow: .lastWeek)
        let q = plan(lib, noFavorites, card: card, manifest: m)
        let reasons2 = Dictionary(uniqueKeysWithValues: q.removals.map { ($0.path, $0.reason) })
        #expect(reasons2 == [
            "Photos/Iceland/gone.jpg": .notInLibrary, "Photos/Norway/3.jpg": .albumNotChosen,
            "Photos/Old/1.jpg": .notInAlbum, "Photos/4.jpg": .notRecent,
        ])

        let off = plan(lib, PhotoSelection(), card: card, manifest: m)
        #expect(off.removals.count == 5 && off.removals.allSatisfy { $0.reason == .photosOff })
        #expect(off.forgotten == [PhotoPlanner.key(assetID: "2", albumID: "ice")])
        #expect(!off.removals.contains { $0.path == "Photos/Mine.jpg" || $0.path == "Photos/Iceland/x.jpg" })
    }

    @Test("A loose photo under All that's now in an album moves to its folder")
    func looseToAlbum() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try write(card, "Photos/1.jpg")
        let lib = PhotoLibraryContents(assets: [photo("1")], albums: [photoAlbum("a", "Trip", .user, ["1"])])
        let p = plan(lib, PhotoSelection(isEnabled: true), card: card, manifest: manifest([record("Photos/1.jpg", asset: "1")]))
        #expect(p.removals.map(\.reason) == [.notInAlbum])
        #expect(p.copies.map(\.destination) == ["Photos/Trip/2024-07-01 IMG_1.jpg"])
    }

    @Test("More than 500 photos in All Photos or an album, or 200 albums, is warned about but still copied")
    func limits() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let assets = (0..<501).map { photo("p\($0)") }
        let lib = PhotoLibraryContents(assets: assets, albums: [photoAlbum("big", "Big", .user, assets.map(\.id))])
        let p = plan(lib, PhotoSelection(isEnabled: true), card: card)
        #expect(p.copies.count == 501)
        #expect(p.overLimit == [PhotoLimitWarning(albumTitle: nil, count: 501),
                                PhotoLimitWarning(albumTitle: "Big", count: 501)])

        let many = PhotoLibraryContents(assets: [photo("1")],
                                        albums: (0..<201).map { photoAlbum("a\($0)", "Album \($0)", .user, ["1"]) })
        #expect(plan(many, PhotoSelection(isEnabled: true), card: card).tooManyAlbums == 201)
    }

    @Test("A folder source isn't built yet: nothing changes, with a note")
    func folderSource() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try write(card, "Photos/1.jpg")
        let s = PhotoSelection(isEnabled: true, source: .folder(bookmark: Data()))
        let p = plan(library, s, card: card, manifest: manifest([record("Photos/1.jpg", asset: "gone")]))
        #expect(p.isEmpty && p.note != nil)
    }

    @Test("File names: the day taken, the original's name, always .jpg")
    func names() {
        #expect(PhotoPlanner.fileName(for: photo("1", name: "Sunset.PNG"), calendar: utc) == "2024-07-01 Sunset.jpg")
        #expect(PhotoPlanner.fileName(for: photo("1", name: " "), calendar: utc) == "2024-07-01 Photo.jpg")
        #expect(PhotoPlanner.fileName(for: photo("1", name: "a:b"), calendar: utc).hasSuffix(".jpg"))
    }

    @Test("Old manifests load without photos; the sync plan counts and words photos")
    func syncPlan() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(SyncManifest.self, from: Data(#"{"formatVersion":1,"entries":{},"playlistFiles":{}}"#.utf8))
        #expect(old.photos == nil)

        let card = try TestCard(); defer { card.cleanUp() }
        var sync = SyncPlan()
        #expect(sync.isEmpty)
        sync.photos = plan(library, PhotoSelection(isEnabled: true), card: card)
        #expect(!sync.isEmpty && sync.allBytesToCopy == sync.photos.bytesToCopy)
        #expect(sync.summary(applyRemovals: false).contains("copy 5 photos (about"))
    }

    @Test("The card listing includes loose photos only when asked")
    func looseListing() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try write(card, "Photos/Loose.jpg"); try write(card, "Photos/A/In.jpg")
        let without = CardFolderListing.scan(folderName: "Photos", on: card.fileSystem)
        let with = CardFolderListing.scan(folderName: "Photos", on: card.fileSystem, includeLooseFiles: true)
        #expect(without.files.count == 1 && with.files.count == 2)
        #expect(with.folders == [CardLayout.caseKey("Photos/A")])
    }
}

// MARK: - Making the JPEGs

/// A test JPEG `width`×`height` with an EXIF orientation and a location.
private func cameraPhoto(width: Int, height: Int, orientation: Int = 1) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 0.8, green: 0.3, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output as CFMutableData, "public.jpeg" as CFString, 1, nil)!
    let properties: [CFString: Any] = [
        kCGImagePropertyOrientation: orientation,
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 64.1, kCGImagePropertyGPSLatitudeRef: "N"],
    ]
    CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
    CGImageDestinationFinalize(destination)
    return output as Data
}

private func properties(_ jpeg: Data) throws -> [CFString: Any] {
    let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
    return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
}

/// Hands out test photos by asset id.
private struct FakePhotos: PhotoRendering {
    let photos: [String: Data]
    func content(for assetID: String, fullResolution: Bool) -> PhotoImageContent? {
        photos[assetID].map { .data($0) }
    }
}

@Suite("Photos on the card: making the JPEGs")
struct PhotoImageTests {

    @Test("Screen copies fit 750 × 580 keeping their shape; full resolution and small photos keep their size")
    func sizes() {
        #expect(PhotoImage.outputSize(width: 4_000, height: 3_000, fullResolution: false) == (750, 563))
        #expect(PhotoImage.outputSize(width: 3_000, height: 4_000, fullResolution: false) == (435, 580))
        #expect(PhotoImage.outputSize(width: 4_000, height: 3_000, fullResolution: true) == (4_000, 3_000))
        #expect(PhotoImage.outputSize(width: 300, height: 200, fullResolution: false) == (300, 200))
        #expect(PhotoImage.outputSize(width: 0, height: 200, fullResolution: false) == (0, 0))
    }

    @Test("Photos become baseline RGB JPEGs, turned upright, with no location or orientation tag")
    func format() throws {
        // Stored 1600 × 1200 but tagged "turn a quarter": upright it's 1200 × 1600.
        let jpeg = try #require(PhotoImage.makeJPEG(from: cameraPhoto(width: 1_600, height: 1_200, orientation: 6),
                                                    fullResolution: false))
        let props = try properties(jpeg)
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 435)
        #expect(props[kCGImagePropertyPixelHeight] as? Int == 580)
        #expect(props[kCGImagePropertyColorModel] as? String == "RGB")
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        #expect((props[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        let bytes = [UInt8](jpeg)
        let hasSOF2 = zip(bytes, bytes.dropFirst()).contains { $0 == 0xFF && $1 == 0xC2 }
        #expect(!hasSOF2)

        let full = try #require(PhotoImage.makeJPEG(from: cameraPhoto(width: 1_600, height: 1_200), fullResolution: true))
        #expect(try properties(full)[kCGImagePropertyPixelWidth] as? Int == 1_600)
        #expect(PhotoImage.makeJPEG(from: Data("not a photo".utf8), fullResolution: false) == nil)
    }

    @Test("An image PhotoKit drew is scaled the same way")
    func fromImage() throws {
        let source = try #require(CGImageSourceCreateWithData(cameraPhoto(width: 2_000, height: 1_000) as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let jpeg = try #require(PhotoImage.makeJPEG(from: .image(image), fullResolution: false))
        #expect(try properties(jpeg)[kCGImagePropertyPixelWidth] as? Int == 750)
        #expect(try properties(jpeg)[kCGImagePropertyPixelHeight] as? Int == 375)
    }
}

// MARK: - Writing and removing

@Suite("Photos on the card: syncing")
struct PhotoExecutorTests {

    private func sync(_ library: PhotoLibraryContents, _ selection: PhotoSelection, card: TestCard,
                      executor: SyncExecutor, removals: Bool = false) async throws -> (PhotoPlan, SyncReport) {
        let manifest = try SyncManifest.load(from: card.fileSystem)
        var sync = SyncPlan()
        sync.photos = plan(library, selection, card: card, manifest: manifest)
        var options = SyncOptions()
        options.applyRemovals = removals
        let report = await executor.run(plan: sync, manifest: manifest, options: options) { _ in }
        return (sync.photos, report)
    }

    @Test("Syncing writes and records photos, a repeat does nothing, and removals take emptied album folders")
    func writesAndRemoves() async throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let logs = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: logs) }
        var executor = SyncExecutor(fileSystem: card.fileSystem, deviceName: "Test", logsDirectory: logs)
        executor.photoRenderer = FakePhotos(photos: Dictionary(uniqueKeysWithValues: ["1", "2", "3", "4"].map {
            ($0, cameraPhoto(width: 1_600, height: 1_200))
        }))
        let on = PhotoSelection(isEnabled: true)

        var (photoPlan, report) = try await sync(library, on, card: card, executor: executor)
        #expect(report.succeeded && report.photosCopied == 5 && report.photosNotRead == 0)
        let shared = card.root.appending(path: "Photos/Norway/2024-07-02 IMG_2.jpg")
        let data = try Data(contentsOf: shared)
        #expect(try properties(data)[kCGImagePropertyPixelWidth] as? Int == 750)
        var manifest = try SyncManifest.load(from: card.fileSystem)
        #expect(manifest.photos?.count == 5)
        #expect(manifest.photos?["2|nor"]?.cardSize == UInt64(data.count))
        #expect(report.bytesCopied == manifest.photos?.values.reduce(0) { $0 + $1.cardSize })

        (photoPlan, _) = try await sync(library, on, card: card, executor: executor)
        #expect(photoPlan.isEmpty && photoPlan.unchangedPhotos == 5)

        // Someone else's photo in an album folder stays, and keeps the folder.
        try write(card, "Photos/Iceland/Mine.jpg")
        // Photos off without "remove": nothing goes.
        (photoPlan, report) = try await sync(library, PhotoSelection(), card: card, executor: executor)
        #expect(photoPlan.removals.count == 5 && report.photosRemoved == 0)
        #expect(FileManager.default.fileExists(atPath: shared.path))
        // With "remove": Q2 Sync's photos go, and Norway's folder with them.
        (_, report) = try await sync(library, PhotoSelection(), card: card, executor: executor, removals: true)
        #expect(report.succeeded && report.photosRemoved == 5)
        #expect(!FileManager.default.fileExists(atPath: card.root.appending(path: "Photos/Norway").path))
        #expect(FileManager.default.fileExists(atPath: card.root.appending(path: "Photos/Iceland/Mine.jpg").path))
        manifest = try SyncManifest.load(from: card.fileSystem)
        #expect(manifest.photos?.isEmpty ?? true)
    }

    @Test("A photo the library can't supply is left for the next sync, not an error")
    func notRead() async throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let logs = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: logs) }
        var executor = SyncExecutor(fileSystem: card.fileSystem, deviceName: "Test", logsDirectory: logs)
        executor.photoRenderer = FakePhotos(photos: ["1": cameraPhoto(width: 100, height: 100)])
        let lib = PhotoLibraryContents(assets: [photo("1"), photo("2", day: 1)], albums: [])
        let (_, report) = try await sync(lib, PhotoSelection(isEnabled: true), card: card, executor: executor)
        #expect(report.succeeded && report.photosCopied == 1 && report.photosNotRead == 1)
        executor.photoRenderer = FakePhotos(photos: ["2": cameraPhoto(width: 100, height: 100)])
        let (photoPlan, again) = try await sync(lib, PhotoSelection(isEnabled: true), card: card, executor: executor)
        #expect(photoPlan.photosToAdd == 1 && again.photosCopied == 1)
    }

    @Test("Turning on full resolution redoes photos in place, and the safety check counts the space they free")
    func fullResolution() async throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let logs = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: logs) }
        var executor = SyncExecutor(fileSystem: card.fileSystem, deviceName: "Test", logsDirectory: logs)
        executor.photoRenderer = FakePhotos(photos: ["1": cameraPhoto(width: 1_600, height: 1_200)])
        let lib = PhotoLibraryContents(assets: [photo("1", size: (1_600, 1_200))], albums: [])
        _ = try await sync(lib, PhotoSelection(isEnabled: true), card: card, executor: executor)
        let oldSize = try SyncManifest.load(from: card.fileSystem).photos?["1|"]?.cardSize ?? 0

        let full = PhotoSelection(isEnabled: true, fullResolution: true)
        let redo = plan(lib, full, card: card, manifest: try SyncManifest.load(from: card.fileSystem))
        #expect(redo.photosToUpdate == 1 && redo.bytesFreedByUpdates == oldSize)
        var redoPlan = SyncPlan(); redoPlan.photos = redo
        let assessment = SyncSafety.assess(plan: redoPlan, health: .healthy, isFirstSync: false,
                                           availableBytes: 1_000_000_000, includeRemovals: false)
        #expect(assessment.projectedFreeBytes == 1_000_000_000 + Int64(oldSize) - Int64(redo.bytesToCopy))

        let (_, report) = try await sync(lib, full, card: card, executor: executor)
        #expect(report.photosCopied == 1)
        let record = try #require(try SyncManifest.load(from: card.fileSystem).photos?["1|"])
        #expect(record.fullResolution && record.path == "Photos/2024-07-01 IMG_1.jpg")
        let data = try Data(contentsOf: card.root.appending(path: record.path))
        #expect(try properties(data)[kCGImagePropertyPixelWidth] as? Int == 1_600)
    }
}

// MARK: - Capacity and automatic syncs

@Suite("Photos on the card: capacity and automatic syncs")
struct PhotoCapacityTests {

    @Test("The capacity bar counts synced photos, photos to add, and photos no longer wanted")
    func capacity() {
        let gb: Int64 = 1_000_000_000
        // On the card: Iceland's two (still wanted) and one from a gone album.
        let m = manifest([record("Photos/Iceland/a.jpg", asset: "1", album: "ice", size: 100_000),
                          record("Photos/Iceland/b.jpg", asset: "2", album: "ice", size: 100_000),
                          record("Photos/Old/c.jpg", asset: "3", album: "gone", size: 50_000)])
        let estimate = CapacityEstimate.compute(totalBytes: 64 * gb, freeBytes: 60 * gb, manifest: m, selection: nil,
                                                photos: (library, PhotoSelection(isEnabled: true)))
        #expect(estimate.photoBytes == 200_000)
        #expect(estimate.deselectedMusicBytes == 50_000)
        // Norway's two and the loose one are to add, at the estimate.
        #expect(estimate.toAddBytes == 3 * Int64(PhotoPlanner.screenCopySize))

        // Not read yet: everything on the card counts as synced, nothing to add.
        let unknown = CapacityEstimate.compute(totalBytes: 64 * gb, freeBytes: 60 * gb, manifest: m, selection: nil)
        #expect(unknown.photoBytes == 250_000 && unknown.toAddBytes == 0)
    }

    @Test("An automatic sync waits for review when photos would be removed")
    func autoSync() throws {
        let card = try TestCard(); defer { card.cleanUp() }
        try write(card, "Photos/Iceland/a.jpg")
        var sync = SyncPlan()
        sync.photos = plan(library, PhotoSelection(), card: card,
                           manifest: manifest([record("Photos/Iceland/a.jpg", asset: "1", album: "ice")]))
        #expect(sync.photos.removals.count == 1)
        guard case .needsReview(let reasons) = AutoSyncPolicy.decide(plan: sync, assessment: SafetyAssessment()) else {
            Issue.record("expected a review"); return
        }
        #expect(reasons == ["1 photo no longer synced would be removed."])
    }
}
