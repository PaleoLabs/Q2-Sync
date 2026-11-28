//
//  ContentHealthTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Unit tests for the Apple Books and Podcasts app "looks healthy" checks,
//  and the sidebar's "Read in 4s" wording.
//
//  SAFETY
//  Temporary folders only. Never touches Apple Books or the Podcasts app.
//

import Foundation
import Testing
@testable import Q2SyncCore

@Suite("Books and Podcasts health")
struct ContentHealthTests {

    private func book(_ id: String, _ availability: TrackAvailability = .available) -> Audiobook {
        Audiobook(id: id, title: id, author: nil, durationSeconds: 60,
                  parts: [AudiobookPart(fileURL: URL(filePath: "/\(id).m4b"), trackNumber: 0, discNumber: 0,
                                        durationSeconds: 60, fileSize: 10)],
                  availability: availability)
    }

    @Test("Apple Books' folder must be reachable")
    func booksFolderMissing() throws {
        let gone = URL(filePath: "/Volumes/Q2SyncTestDriveThatDoesNotExist/Books")
        #expect(!AudiobookHealthCheck.evaluate([book("a")], selection: nil, folder: gone).isHealthy)

        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(AudiobookHealthCheck.evaluate([book("a")], selection: nil, folder: folder).isHealthy)
        // No books at all is fine (Apple Books just has none).
        #expect(AudiobookHealthCheck.evaluate([], selection: nil, folder: folder).isHealthy)
    }

    @Test("Chosen books missing in bulk is unsafe; others don't count")
    func booksMissingInBulk() {
        let books = (0..<9).map { book("ok\($0)") } + [book("gone0", .fileMissing), book("gone1", .fileMissing)]
        // Every book: 2 of 11 missing (18%).
        #expect(!AudiobookHealthCheck.evaluate(books, selection: nil, folder: nil).isHealthy)

        // A Q2 that chooses only the books whose files are there.
        let chosen = AudiobookSelection(isEnabled: true, includesAll: false,
                                        bookIDs: Set((0..<9).map { "ok\($0)" }))
        #expect(AudiobookHealthCheck.evaluate(books, selection: chosen, folder: nil).isHealthy)

        // "All" counts every book again.
        let all = AudiobookSelection(isEnabled: true, includesAll: true)
        #expect(!AudiobookHealthCheck.evaluate(books, selection: all, folder: nil).isHealthy)
    }

    @Test("Cloud-only and protected books don't count as missing")
    func booksCloudAndProtectedIgnored() {
        let books = [book("ok")] + (0..<10).map { book("c\($0)", .cloudOnly) }
            + (0..<10).map { book("p\($0)", .drmProtected) }
        #expect(AudiobookHealthCheck.evaluate(books, selection: nil, folder: nil).isHealthy)
    }

    @Test("Podcasts needs its database and downloads folder; no episodes is fine")
    func podcasts() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fm = FileManager.default
        #expect(!PodcastHealthCheck.evaluate(folder: folder).isHealthy)

        let database = folder.appending(path: ApplePodcastsSource.databasePath)
        try fm.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: database)
        #expect(!PodcastHealthCheck.evaluate(folder: folder).isHealthy) // No downloads folder yet.

        try fm.createDirectory(at: folder.appending(path: ApplePodcastsSource.downloadsPath),
                               withIntermediateDirectories: true)
        // An empty downloads folder: played downloads are deleted by default.
        #expect(PodcastHealthCheck.evaluate(folder: folder).isHealthy)
    }

    @Test("Photos needs access; an empty library is fine")
    func photos() {
        #expect(PhotoHealthCheck.evaluate(isAllowed: true).isHealthy)
        #expect(!PhotoHealthCheck.evaluate(isAllowed: false).isHealthy)
    }

    @Test("Read time: whole seconds, one decimal under a second")
    func readTime() {
        let us = Locale(identifier: "en_US")
        #expect(ReadTimeWording.text(.milliseconds(3_968), locale: us) == "Read in 4s")
        #expect(ReadTimeWording.text(.milliseconds(1_200), locale: us) == "Read in 1s")
        #expect(ReadTimeWording.text(.milliseconds(420), locale: us) == "Read in 0.4s")
        #expect(ReadTimeWording.text(.milliseconds(970), locale: us) == "Read in 1s")
        #expect(ReadTimeWording.text(.milliseconds(3), locale: us) == "Read in 0.1s")
        #expect(ReadTimeWording.text(.milliseconds(420), locale: Locale(identifier: "fr_FR")) == "Read in 0,4s")
    }
}
