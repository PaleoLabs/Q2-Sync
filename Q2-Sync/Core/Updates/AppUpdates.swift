//
//  AppUpdates.swift
//  Q2-Sync › Core › Updates
//
//  PURPOSE
//  Checks GitHub for a newer release of Q2 Sync itself. It only reads which
//  release is the latest: nothing is downloaded or installed. You get the
//  new version from the release's web page.
//
//  HOW IT FITS
//  `AppUpdateModel` (App) decides when to check and what to show. Versions
//  are compared with `FirmwareVersion`, and problems are reported as
//  `FirmwareCheckError`: both work the same for any GitHub release.
//
//  RELEASING
//  A release's tag ("v0.3.0") is compared with the app's MARKETING_VERSION
//  ("0.3"). If a release is tagged without bumping that setting first,
//  everyone who installs it is told it's still available.
//

import Foundation

/// One release of Q2 Sync from GitHub.
struct AppRelease: Sendable, Equatable {
    /// The release tag, e.g. "v0.3.0".
    let tag: String

    /// The version as shown to people: the tag without its "v".
    var version: String {
        tag.lowercased().hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Whether this release is newer than the running app.
    ///
    /// - Parameter current: The app's version, e.g. "0.2".
    /// - Returns: `false` if either version can't be read.
    func isNewer(than current: String) -> Bool {
        guard let release = FirmwareVersion(tag), let running = FirmwareVersion(current) else { return false }
        return release > running
    }

    /// The fields we read from GitHub's JSON.
    private struct GitHubJSON: Decodable {
        let tag_name: String
        let draft: Bool?
        let prerelease: Bool?
    }

    /// Parses GitHub's "latest release" JSON.
    ///
    /// - Parameter data: The API response body.
    /// - Returns: The release.
    /// - Throws: `FirmwareCheckError.unexpectedResponse` for drafts,
    ///   pre-releases, unreadable JSON or a tag with no version in it.
    static func parseGitHub(_ data: Data) throws -> AppRelease {
        guard let json = try? JSONDecoder().decode(GitHubJSON.self, from: data),
              json.draft != true, json.prerelease != true,
              FirmwareVersion(json.tag_name) != nil else {
            throw FirmwareCheckError.unexpectedResponse
        }
        return AppRelease(tag: json.tag_name)
    }
}

/// Q2 Sync update checking.
enum AppUpdateChecker {

    /// GitHub's "latest release" endpoint for Q2 Sync.
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/PaleoLabs/Q2-Sync/releases/latest")!

    /// The web page of the latest release. A fixed address: nothing GitHub
    /// answers is ever opened.
    static let downloadPage = URL(string: "https://github.com/PaleoLabs/Q2-Sync/releases/latest")!

    /// Fetches the latest Q2 Sync release (read-only HTTPS request).
    ///
    /// - Parameter session: The URL session (tests could inject one).
    /// - Returns: The latest release.
    /// - Throws: Network or parsing errors.
    /// - Side effects: One request to api.github.com. No personal details
    ///   are sent, not even the version you have; the User-Agent is just
    ///   "Q2-Sync".
    static func fetchLatest(session: URLSession = .shared) async throws -> AppRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Q2-Sync", forHTTPHeaderField: "User-Agent") // GitHub requires one.
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw FirmwareCheckError.httpStatus(http.statusCode)
        }
        return try AppRelease.parseGitHub(data)
    }
}
