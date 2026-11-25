//
//  FinderRevealTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Tests what "Show in Finder" selects for a group of songs.
//

import Foundation
import Testing
@testable import Q2SyncCore

private func files(_ paths: String...) -> [URL] {
    paths.map { URL(filePath: "/Music/\($0)") }
}

@Suite("Show in Finder for a group")
struct FinderRevealTests {

    @Test("An album's songs are selected in their folder")
    func oneFolder() {
        let songs = files("Artist/Album/1.mp3", "Artist/Album/2.mp3")
        #expect(FinderReveal.items(for: songs) == songs)
    }

    @Test("An artist's album folders are selected in the artist folder")
    func siblingFolders() {
        let items = FinderReveal.items(for: files("Artist/B/1.mp3", "Artist/A/1.mp3", "Artist/A/2.mp3"))
        #expect(items?.map(\.lastPathComponent) == ["A", "B"])
    }

    @Test("Songs spread further apart can't be shown in one window")
    func scattered() {
        #expect(FinderReveal.items(for: files("One/A/1.mp3", "Two/B/1.mp3")) == nil)
    }

    @Test("No files, nothing to show")
    func empty() {
        #expect(FinderReveal.items(for: []) == nil)
    }
}
