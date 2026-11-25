//
//  FirmwareSources.swift
//  Q2-Sync › Core › Device
//
//  PURPOSE
//  Where each firmware is downloaded from, as a `FirmwareOffer`: a version,
//  a link, and what the download should look like.
//
//  THE SOURCES (checked 2026-11-21)
//  • Q2 Pod: the latest GitHub release's `update.tar`, with GitHub's own
//    SHA-256 of it (see `FirmwareRelease`). The download must match.
//  • Shanling stock: Shanling's Q2 download page
//    (https://en.shanling.com/download/150) says "Shanling Q2 Firmware
//    V1.36" and links a Google Drive file, "Q2 Firmware V1.36.zip", with
//    one `update.tar` inside. There's no checksum, so the file is checked
//    by its contents instead (`FirmwareImage.inspect`: model "Shanling Q2",
//    a stock version) and the zip's own CRC-32.
//    Google Drive shows a "can't scan for viruses" page for files this big;
//    the `confirm=t` link skips it and returns the file. If Shanling or
//    Google change their pages, the app falls back to letting you download
//    the file yourself and choose it (see `FirmwareInstaller`).
//
//  Q2 Pod's README describes going back to stock the same way: install
//  Shanling's official firmware from that page.
//

import Foundation

/// How a firmware download is packaged.
enum FirmwarePackaging: String, Codable, Sendable {
    /// The `update.tar` itself.
    case tar
    /// A zip with an `update.tar` inside.
    case zip
}

/// One firmware the user can install.
struct FirmwareOffer: Equatable, Sendable {
    /// Which firmware.
    let kind: FirmwareKind
    /// Its version for people, e.g. "1.8.9" or "1.36".
    let version: String
    /// The download link.
    let downloadURL: URL
    /// How the download is packaged.
    let packaging: FirmwarePackaging
    /// The expected SHA-256 of the `update.tar`, when the source gives one.
    let expectedSHA256: String?
    /// The expected download size, when known.
    let expectedSize: Int64?
    /// A web page about this firmware (release notes / download page).
    let infoPage: URL

    /// e.g. "Q2 Pod 1.8.9" or "Shanling (stock) V1.36".
    var displayName: String {
        kind == .q2Pod ? "Q2 Pod \(version)" : "Shanling (stock) V\(version)"
    }
}

/// Problems finding a download.
enum FirmwareSourceError: LocalizedError, Equatable {
    case noUpdateFile
    case shanlingPageChanged
    case shanlingHTTPStatus(Int)

    var errorDescription: String? {
        switch self {
        case .noUpdateFile: return "The latest Q2 Pod release has no update.tar to download."
        case .shanlingPageChanged: return "Shanling's download page has changed, so Q2 Sync can't find the firmware on it."
        case .shanlingHTTPStatus(let code): return "Shanling's download page answered with an error (\(code)). Try again later."
        }
    }
}

/// Building offers from each source's answer.
enum FirmwareSources {

    /// GitHub's page listing Q2 Pod releases (for the manual fallback).
    static let q2PodReleasesPage = URL(string: "https://github.com/DiamondBond/q2-pod/releases/latest")!

    /// Shanling's Q2 download page.
    static let stockDownloadPage = URL(string: "https://en.shanling.com/download/150")!

    /// Shanling's recovery package, linked from Q2 Pod's README for a Q2
    /// that won't start up after an update.
    static let recoveryHelpPage = URL(string: "https://github.com/DiamondBond/q2-pod#restoring-stock-firmware")!

    /// The offer for a Q2 Pod release.
    ///
    /// - Parameter release: The latest release, from `FirmwareUpdateChecker`.
    /// - Returns: The offer.
    /// - Throws: `FirmwareSourceError.noUpdateFile` if it has no `update.tar`.
    static func q2PodOffer(from release: FirmwareRelease) throws -> FirmwareOffer {
        guard let file = release.updateFile else { throw FirmwareSourceError.noUpdateFile }
        return FirmwareOffer(kind: .q2Pod, version: FirmwareVersion(release.tag)?.description ?? release.tag,
                             downloadURL: file.url, packaging: .tar, expectedSHA256: file.sha256,
                             expectedSize: file.size, infoPage: release.pageURL)
    }

    /// Reads Shanling's download page for the latest stock firmware
    /// (read-only HTTPS request; nothing is downloaded).
    ///
    /// - Parameter session: The URL session (tests could inject one).
    /// - Returns: The offer.
    /// - Throws: Network errors or `FirmwareSourceError`.
    /// - Side effects: One request to en.shanling.com. No personal details
    ///   are sent; the User-Agent is just "Q2-Sync".
    static func fetchStockOffer(session: URLSession = .shared) async throws -> FirmwareOffer {
        var request = URLRequest(url: stockDownloadPage)
        request.setValue("Q2-Sync", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw FirmwareSourceError.shanlingHTTPStatus(http.statusCode)
        }
        return try stockOffer(fromShanlingPage: String(decoding: data, as: UTF8.self))
    }

    /// Finds the stock firmware's version and download on Shanling's page.
    ///
    /// Looks for "Shanling Q2 Firmware V1.36" and the first Google Drive
    /// file link ("drive.google.com/file/d/<id>/…").
    ///
    /// - Parameter html: The page's HTML.
    /// - Returns: The offer.
    /// - Throws: `FirmwareSourceError.shanlingPageChanged` if either is missing.
    static func stockOffer(fromShanlingPage html: String) throws -> FirmwareOffer {
        guard let versionMatch = html.firstMatch(of: /Q2\s+Firmware\s+V(\d+(?:\.\d+)+)/),
              let linkMatch = html.firstMatch(of: /drive\.google\.com\/file\/d\/([A-Za-z0-9_-]{10,})/) else {
            throw FirmwareSourceError.shanlingPageChanged
        }
        return FirmwareOffer(kind: .stock, version: String(versionMatch.1),
                             downloadURL: driveDownloadURL(fileID: String(linkMatch.1)),
                             packaging: .zip, expectedSHA256: nil, expectedSize: nil,
                             infoPage: stockDownloadPage)
    }

    /// Google Drive's direct download link for a shared file, past the
    /// "can't scan for viruses" page.
    static func driveDownloadURL(fileID: String) -> URL {
        var components = URLComponents(string: "https://drive.usercontent.google.com/download")!
        components.queryItems = [
            URLQueryItem(name: "id", value: fileID),
            URLQueryItem(name: "export", value: "download"),
            URLQueryItem(name: "confirm", value: "t"),
        ]
        return components.url!
    }
}
