//
//  ContentHealthCheck.swift
//  Q2-Sync › Core › Library
//
//  PURPOSE
//  The "looks healthy" checks for Apple Books and the Podcasts app, the
//  counterparts of the Music library's `LibraryHealthCheck`, plus the
//  "Read in 4s" wording shared by the sidebar footers.
//
//  WHY IT MATTERS
//  A Books folder that can't be reached, or a Podcasts app whose database
//  is gone, can look like "no books" or "no episodes". A sync would then
//  remove everything of that kind from the card. When a check fails, the
//  sync leaves that kind as it is on the card instead (`SyncCoordinator`).
//
//  HOW IT FITS
//  `AppleBooksSource` and `ApplePodcastsSource` call these through their
//  `health` methods. The footers show the result; `SyncCoordinator` acts on it.
//

import Foundation

/// Decides whether a list of audiobooks read from Apple Books can be trusted.
enum AudiobookHealthCheck {

    /// If more than this fraction of the chosen books' files are missing,
    /// assume something is wrong with Apple Books' folder and stop.
    static let maximumMissingFraction = LibraryHealthCheck.maximumMissingFraction

    /// Checks the books just read.
    ///
    /// - Parameters:
    ///   - books: The books read from Apple Books.
    ///   - selection: A Q2's audiobook choice: only the books it chooses
    ///     count towards "missing in bulk". `nil` counts every book.
    ///   - folder: Apple Books' folder, which must be reachable. `nil`
    ///     skips that rule (fixtures).
    ///   - fileManager: Injectable for tests.
    /// - Returns: `.healthy`, or `.unsafe` with the reason.
    /// - Side effects: None. Only checks whether the folder exists.
    static func evaluate(_ books: [Audiobook], selection: AudiobookSelection?,
                         folder: URL?, fileManager: FileManager = .default) -> LibraryHealth {
        // Rule 1: the folder must be reachable.
        if let folder {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return .unsafe("Apple Books' folder isn't available, so Q2 Sync can't tell which audiobooks you have.")
            }
        }

        // Rule 2: the chosen books' files mustn't be missing in bulk.
        // Cloud-only and protected books don't count: they were never
        // going to sync, and they aren't a sign of trouble.
        let chosen = books.filter { book in
            guard let selection else { return true }
            return selection.includesAll || selection.bookIDs.contains(book.id)
        }
        let missing = chosen.count { $0.availability == .fileMissing }
        let local = missing + chosen.count { $0.availability == .available }
        if local > 0 {
            let fraction = Double(missing) / Double(local)
            if fraction > maximumMissingFraction {
                let percent = Int((fraction * 100).rounded())
                return .unsafe("\(percent)% of your audiobooks' files can't be found in Apple Books' folder.")
            }
        }
        return .healthy
    }
}

/// Decides whether the Podcasts app's downloads can be trusted.
enum PodcastHealthCheck {

    /// Checks the Podcasts app's folder.
    ///
    /// An empty episode list is still trusted: the Podcasts app deletes
    /// played downloads by default, so "nothing downloaded" is normal.
    ///
    /// - Parameters:
    ///   - folder: The Podcasts app's folder (the one access was allowed to).
    ///   - fileManager: Injectable for tests.
    /// - Returns: `.healthy`, or `.unsafe` with the reason.
    /// - Side effects: None. Only checks that two items exist.
    static func evaluate(folder: URL, fileManager: FileManager = .default) -> LibraryHealth {
        let database = folder.appending(path: ApplePodcastsSource.databasePath)
        guard fileManager.isReadableFile(atPath: database.path) else {
            return .unsafe("The Podcasts app's database can't be opened, so Q2 Sync can't tell which episodes you have.")
        }
        var isDirectory: ObjCBool = false
        let downloads = folder.appending(path: ApplePodcastsSource.downloadsPath, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: downloads.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .unsafe("The Podcasts app's downloads folder isn't there, so Q2 Sync can't tell which episodes you have.")
        }
        return .healthy
    }
}

/// How long reading a library took, for the sidebar footers.
enum ReadTimeWording {

    /// "Read in 4s", or one decimal under a second: "Read in 0.4s".
    ///
    /// - Parameters:
    ///   - duration: How long the read took.
    ///   - locale: For the decimal separator. Injectable for tests.
    static func text(_ duration: Duration, locale: Locale = .current) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        if seconds < 0.95 {
            // At least 0.1s, so a very fast read never says "0.0s".
            let tenths = max(0.1, (seconds * 10).rounded() / 10)
            return "Read in \(tenths.formatted(.number.precision(.fractionLength(1)).locale(locale)))s"
        }
        return "Read in \(Int(seconds.rounded()))s"
    }
}
