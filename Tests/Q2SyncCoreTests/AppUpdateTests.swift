//
//  AppUpdateTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Tests for reading GitHub's answer about the latest Q2 Sync release and
//  deciding whether it's newer than the running app. No network is used.
//

import Foundation
import Testing
@testable import Q2SyncCore

@Suite("App updates")
struct AppUpdateTests {

    @Test("Reads the tag from GitHub's answer")
    func parses() throws {
        let release = try AppRelease.parseGitHub(Data(#"""
        {"tag_name": "v0.3.0", "name": "Q2 Sync 0.3.0", "draft": false, "prerelease": false}
        """#.utf8))
        #expect(release.tag == "v0.3.0")
        #expect(release.version == "0.3.0")
    }

    @Test("Refuses drafts, pre-releases, tags with no version and other answers", arguments: [
        #"{"tag_name": "v0.3.0", "draft": true}"#,
        #"{"tag_name": "v0.3.0", "prerelease": true}"#,
        #"{"tag_name": "nightly"}"#,
        #"{"message": "Not Found"}"#,
        "<html></html>",
    ])
    func refuses(json: String) {
        #expect(throws: FirmwareCheckError.unexpectedResponse) {
            try AppRelease.parseGitHub(Data(json.utf8))
        }
    }

    @Test("A newer release is offered", arguments: [
        ("v0.3.0", "0.2"), ("v0.2.1", "0.2"), ("v1.0.0", "0.9"), ("v0.10.0", "0.9"),
    ])
    func newer(tag: String, current: String) {
        #expect(AppRelease(tag: tag).isNewer(than: current))
    }

    @Test("The same or an older release isn't", arguments: [
        ("v0.2.0", "0.2"), ("v0.2", "0.2.0"), ("v0.1.0", "0.2"), ("v0.2.0", "0.3"), ("v0.3.0", ""),
    ])
    func notNewer(tag: String, current: String) {
        #expect(!AppRelease(tag: tag).isNewer(than: current))
    }
}
