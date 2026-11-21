//
//  AlbumCoverTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Tests for album covers (planning, the JPEG they're written as, writing
//  and removing them on a test card) and for the sync's time estimate.
//  No real library: artwork comes from a fake provider.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Q2SyncCore

/// Artwork from a dictionary instead of the library.
struct FakeArtwork: AlbumArtworkProviding {
    let images: [PersistentID: Data]
    func artworkData(for trackID: PersistentID) -> Data? { images[trackID] }
}

/// A test image: `width`×`height`, PNG with transparency by default.
func makeImage(width: Int, height: Int, type: UTType = .png) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 0.5))
    context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}

/// A track with artwork, in a given album.
func artTrack(_ id: String, album: String = "Album", number: Int = 1, art: Bool = true,
              fileURL: URL = URL(filePath: "/tmp/none.mp3"), size: UInt64 = 1_000) -> Track {
    var track = makeCopyableTrack(id: id, title: "Song \(id)", album: album, number: number, size: size, fileURL: fileURL)
    track.hasArtwork = art
    return track
}

@Suite("Album covers")
struct AlbumCoverTests {

    func files(_ paths: [CardPath]) -> [String: CardFile] {
        Dictionary(paths.map { (CardLayout.caseKey($0), CardFile(path: $0, size: 10)) }, uniquingKeysWith: { a, _ in a })
    }

    @Test("One cover per album folder, from the first track with artwork")
    func onePerFolder() {
        let tracks = [artTrack("B", number: 2), artTrack("A", number: 1, art: false), artTrack("C", album: "Other")]
        let paths: [PersistentID: CardPath] = ["A": "Music/Artist/Album/01 A.mp3", "B": "Music/Artist/Album/02 B.mp3",
                                               "C": "Music/Artist/Other/01 C.mp3"]
        let writes = AlbumCovers.plan(tracks: tracks, finalPaths: paths, manifest: SyncManifest(), cardFiles: [:])
        #expect(writes.map(\.path) == ["Music/Artist/Album/cover.jpg", "Music/Artist/Other/cover.jpg"])
        #expect(writes.first?.trackID == "B") // A has no artwork
    }

    @Test("Albums without artwork get no cover")
    func noArtwork() {
        let writes = AlbumCovers.plan(tracks: [artTrack("A", art: false)], finalPaths: ["A": "Music/X/Y/01 A.mp3"],
                                      manifest: SyncManifest(), cardFiles: [:])
        #expect(writes.isEmpty)
    }

    @Test("Your own cover or folder image is never replaced", arguments: ["cover.jpg", "Folder.JPG", "cover.png"])
    func respectsOwnArt(name: String) {
        let writes = AlbumCovers.plan(tracks: [artTrack("A")], finalPaths: ["A": "Music/X/Y/01 A.mp3"],
                                      manifest: SyncManifest(), cardFiles: files(["Music/X/Y/\(name)"]))
        #expect(writes.isEmpty)
    }

    @Test("Q2 Sync's own cover is kept, rewritten if missing or its source changed")
    func ownCover() {
        let track = artTrack("A")
        var manifest = SyncManifest()
        manifest.albumCovers = ["Music/X/Y/cover.jpg": .init(sourceKey: AlbumCovers.sourceKey(for: track), writtenAt: .now)]
        let paths: [PersistentID: CardPath] = ["A": "Music/X/Y/01 A.mp3"]
        #expect(AlbumCovers.plan(tracks: [track], finalPaths: paths, manifest: manifest,
                                 cardFiles: files(["Music/X/Y/cover.jpg"])).isEmpty)
        #expect(AlbumCovers.plan(tracks: [track], finalPaths: paths, manifest: manifest, cardFiles: [:]).count == 1)
        manifest.albumCovers?["Music/X/Y/cover.jpg"]?.sourceKey = "OTHER@0"
        #expect(AlbumCovers.plan(tracks: [track], finalPaths: paths, manifest: manifest,
                                 cardFiles: files(["Music/X/Y/cover.jpg"])).count == 1)
    }

    @Test("The planner adds covers only when asked, and counts them as work")
    func plannerOption() {
        let tracks = [artTrack("A")]
        let selection = resolved(tracks)
        let off = SyncPlanner.plan(selection: selection, allSelectedIDs: ["A"], manifest: SyncManifest(),
                                   cardFiles: [:], layout: CardLayout(profile: .q2Pod))
        #expect(off.coverWrites.isEmpty)
        let on = SyncPlanner.plan(selection: selection, allSelectedIDs: ["A"], manifest: SyncManifest(),
                                  cardFiles: [:], layout: CardLayout(profile: .q2Pod), albumCovers: true)
        #expect(on.coverWrites.map(\.path) == ["Music/Artist/Album/cover.jpg"])
        #expect(!on.isEmpty)
    }

    @Test("Covers are baseline RGB JPEGs no bigger than 1000 px")
    func jpegFormat() throws {
        let jpeg = try #require(CoverImage.makeJPEG(from: makeImage(width: 2400, height: 1200)))
        #expect(jpeg.starts(with: [0xFF, 0xD8]))
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 1000)
        #expect(props[kCGImagePropertyPixelHeight] as? Int == 500)
        #expect(props[kCGImagePropertyColorModel] as? String == "RGB")
        // Baseline JPEGs have an SOF0 marker (FF C0); progressive ones SOF2 (FF C2).
        let bytes = [UInt8](jpeg)
        let hasSOF0 = zip(bytes, bytes.dropFirst()).contains { $0 == 0xFF && $1 == 0xC0 }
        let hasSOF2 = zip(bytes, bytes.dropFirst()).contains { $0 == 0xFF && $1 == 0xC2 }
        #expect(hasSOF0 && !hasSOF2)
        // Small artwork keeps its size; junk gives nothing.
        let small = try #require(CoverImage.makeJPEG(from: makeImage(width: 300, height: 300, type: .jpeg)))
        let smallProps = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithData(small as CFData, nil)!, 0, nil)
            as? [CFString: Any]
        #expect(smallProps?[kCGImagePropertyPixelWidth] as? Int == 300)
        #expect(CoverImage.makeJPEG(from: Data("not an image".utf8)) == nil)
    }

    @Test("Syncing writes covers, records them, and removes them with their album")
    func executorWritesAndRemoves() async throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let mac = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: mac) }
        let logs = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: logs) }
        let source = mac.appending(path: "a.mp3")
        try Data(repeating: 7, count: 2_000).write(to: source)
        let track = artTrack("A", fileURL: source, size: 2_000)
        let layout = CardLayout(profile: .q2Pod)

        // Sync with covers on.
        var manifest = try SyncManifest.load(from: card.fileSystem)
        var plan = SyncPlanner.plan(selection: resolved([track]), allSelectedIDs: ["A"], manifest: manifest,
                                    cardFiles: CardScanner.scan(folder: "Music", on: card.fileSystem),
                                    layout: layout, albumCovers: true)
        var executor = SyncExecutor(fileSystem: card.fileSystem, deviceName: "Test", logsDirectory: logs)
        executor.artwork = FakeArtwork(images: ["A": makeImage(width: 600, height: 600)])
        var report = await executor.run(plan: plan, manifest: manifest, options: SyncOptions()) { _ in }
        #expect(report.succeeded && report.coversWritten == 1)
        let cover = card.root.appending(path: "Music/Artist/Album/cover.jpg")
        #expect(FileManager.default.fileExists(atPath: cover.path))
        manifest = try SyncManifest.load(from: card.fileSystem)
        #expect(manifest.albumCovers?["Music/Artist/Album/cover.jpg"] != nil)

        // A repeat sync has nothing to do.
        plan = SyncPlanner.plan(selection: resolved([track]), allSelectedIDs: ["A"], manifest: manifest,
                                cardFiles: CardScanner.scan(folder: "Music", on: card.fileSystem),
                                layout: layout, albumCovers: true)
        #expect(plan.isEmpty)

        // Deselect the album and apply removals: the cover and folder go too.
        plan = SyncPlanner.plan(selection: resolved([]), allSelectedIDs: [], manifest: manifest,
                                cardFiles: CardScanner.scan(folder: "Music", on: card.fileSystem),
                                layout: layout, albumCovers: true)
        var options = SyncOptions(); options.applyRemovals = true; options.moveRemovalsToTrash = false
        options.largeRemovalConfirmed = true
        report = await executor.run(plan: plan, manifest: manifest, options: options) { _ in }
        #expect(report.succeeded && report.coversRemoved == 1)
        #expect(!FileManager.default.fileExists(atPath: cover.path))
        #expect(!FileManager.default.fileExists(atPath: card.root.appending(path: "Music/Artist/Album").path))
        #expect(try SyncManifest.load(from: card.fileSystem).albumCovers?.isEmpty ?? true)
    }

    @Test("Turning covers on adds them; turning them off removes only Q2 Sync's")
    func toggling() async throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let mac = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: mac) }
        let logs = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: logs) }
        let sourceA = mac.appending(path: "a.mp3"), sourceB = mac.appending(path: "b.mp3")
        try Data(repeating: 1, count: 1_500).write(to: sourceA)
        try Data(repeating: 2, count: 1_600).write(to: sourceB)
        let tracks = [artTrack("A", album: "One", fileURL: sourceA, size: 1_500),
                      artTrack("B", album: "Two", fileURL: sourceB, size: 1_600)]
        var executor = SyncExecutor(fileSystem: card.fileSystem, deviceName: "Test", logsDirectory: logs)
        executor.artwork = FakeArtwork(images: ["A": makeImage(width: 64, height: 64),
                                                "B": makeImage(width: 64, height: 64)])
        func sync(covers: Bool) async throws -> (SyncPlan, SyncReport) {
            let manifest = try SyncManifest.load(from: card.fileSystem)
            let plan = SyncPlanner.plan(selection: resolved(tracks), allSelectedIDs: ["A", "B"], manifest: manifest,
                                        cardFiles: CardScanner.scan(folder: "Music", on: card.fileSystem),
                                        layout: CardLayout(profile: .q2Pod), albumCovers: covers)
            let report = await executor.run(plan: plan, manifest: manifest, options: SyncOptions()) { _ in }
            return (plan, report)
        }
        let coverOne = card.root.appending(path: "Music/Artist/One/cover.jpg")
        let ownCover = card.root.appending(path: "Music/Artist/Two/folder.jpg")

        // Off: songs only, no covers.
        var (plan, report) = try await sync(covers: false)
        #expect(plan.coverWrites.isEmpty && plan.coverRemovals.isEmpty && report.added == 2)
        #expect(!FileManager.default.fileExists(atPath: coverOne.path))
        // The user adds their own art to album Two.
        try Data("mine".utf8).write(to: ownCover)

        // Turned on later: covers for the songs already on the card (not Two).
        (plan, report) = try await sync(covers: true)
        #expect(plan.copies.isEmpty && plan.coverWrites.map(\.path) == ["Music/Artist/One/cover.jpg"])
        #expect(report.coversWritten == 1 && FileManager.default.fileExists(atPath: coverOne.path))

        // Turned off again: Q2 Sync's cover goes; songs and the user's art stay.
        (plan, report) = try await sync(covers: false)
        #expect(plan.coverRemovals == ["Music/Artist/One/cover.jpg"])
        #expect(report.succeeded && report.coversRemoved == 1)
        #expect(!FileManager.default.fileExists(atPath: coverOne.path))
        #expect(FileManager.default.fileExists(atPath: card.root.appending(path: "Music/Artist/One/01 Song A.mp3").path))
        #expect(try Data(contentsOf: ownCover) == Data("mine".utf8))
        #expect(try SyncManifest.load(from: card.fileSystem).albumCovers?.isEmpty ?? true)

        // And nothing left to do while off.
        (plan, _) = try await sync(covers: false)
        #expect(plan.isEmpty)
    }

    @Test("A user's own cover.jpg is never touched by syncing")
    func executorLeavesUserCover() async throws {
        let card = try TestCard(); defer { card.cleanUp() }
        let logs = try makeTempFolder(); defer { try? FileManager.default.removeItem(at: logs) }
        let folder = card.root.appending(path: "Music/Artist/Album")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: folder.appending(path: "cover.jpg"))
        try Data(repeating: 1, count: 1_000).write(to: folder.appending(path: "01 Song A.mp3"))
        let track = artTrack("A")
        let manifest = try SyncManifest.load(from: card.fileSystem)
        let plan = SyncPlanner.plan(selection: resolved([track]), allSelectedIDs: ["A"], manifest: manifest,
                                    cardFiles: CardScanner.scan(folder: "Music", on: card.fileSystem),
                                    layout: CardLayout(profile: .q2Pod), albumCovers: true)
        #expect(plan.coverWrites.isEmpty)
        var executor = SyncExecutor(fileSystem: card.fileSystem, deviceName: "Test", logsDirectory: logs)
        executor.artwork = FakeArtwork(images: ["A": makeImage(width: 100, height: 100)])
        _ = await executor.run(plan: plan, manifest: manifest, options: SyncOptions()) { _ in }
        #expect(try Data(contentsOf: folder.appending(path: "cover.jpg")) == Data("mine".utf8))
    }

    @Test("Manifests from before covers still load")
    func oldManifest() throws {
        let json = #"{"formatVersion":1,"entries":{},"playlistFiles":{}}"#
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(SyncManifest.self, from: Data(json.utf8)).albumCovers == nil)
    }
}

@Suite("Time remaining")
struct TimeRemainingTests {

    @Test("Waits for enough data, then estimates from the copying speed")
    func estimates() {
        var estimator = TimeRemainingEstimator()
        let total: UInt64 = 1_000_000_000
        #expect(estimator.update(bytesCopied: 0, totalBytes: total, at: 0) == nil)
        #expect(estimator.update(bytesCopied: 10_000_000, totalBytes: total, at: 100) == nil) // starts here
        #expect(estimator.update(bytesCopied: 40_000_000, totalBytes: total, at: 105) == nil) // too soon
        // 10 MB/s steady: 200 MB copied 20 s after starting at 10 MB.
        let remaining = estimator.update(bytesCopied: 210_000_000, totalBytes: total, at: 120)
        #expect(remaining.map { abs($0 - 79) < 1 } == true)
    }

    @Test("No copying, no estimate")
    func nothingToCopy() {
        var estimator = TimeRemainingEstimator()
        #expect(estimator.update(bytesCopied: 0, totalBytes: 0, at: 50) == nil)
    }

    static let wordings: [(Double, String)] = [
        (30, "Less than a minute remaining"), (89, "About 1 minute remaining"),
        (720, "About 12 minutes remaining"), (3600, "About 1 hour remaining"),
        (4920, "About 1 hour 20 minutes remaining"), (10680, "About 3 hours remaining"),
    ]

    @Test("Friendly wording", arguments: wordings)
    func wording(seconds: Double, text: String) {
        #expect(TimeRemainingEstimator.describe(seconds) == text)
    }
}
