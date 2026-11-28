//
//  PhotoNameCacheTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Tests for the cache of photos' original file names that makes reading
//  the Photos library fast after the first time (#68).
//
//  SAFETY
//  In-memory values and temp folders only.
//

import Foundation
import Testing
@testable import Q2SyncCore

@Suite("Photo name cache")
struct PhotoNameCacheTests {

    func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "Photo Names.json")
    }

    @Test("Saves and loads entries, including photos with no name")
    func roundTrip() {
        let url = tempURL()
        var cache = PhotoNameCache()
        cache["a"] = .init(name: "IMG_0001.HEIC", type: "public.heic")
        cache["b"] = .init(name: nil, type: nil)
        cache.save(to: url)

        let loaded = PhotoNameCache.load(from: url)
        #expect(loaded == cache)
        #expect(loaded["a"]?.name == "IMG_0001.HEIC")
        #expect(loaded["b"] != nil) // "No name" is remembered, not looked up again.
        #expect(loaded["c"] == nil)
    }

    @Test("A missing or unreadable file gives an empty cache")
    func missingOrBadFile() throws {
        let url = tempURL()
        #expect(PhotoNameCache.load(from: url).entries.isEmpty)

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        #expect(PhotoNameCache.load(from: url).entries.isEmpty)
    }

    @Test("A file from another format version is ignored")
    func otherVersion() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let json = #"{"version": 999, "entries": {"a": {"name": "x.jpg"}}}"#
        try Data(json.utf8).write(to: url)
        #expect(PhotoNameCache.load(from: url).entries.isEmpty)
    }

    @Test("keepOnly forgets photos no longer in the library")
    func keepOnly() {
        var cache = PhotoNameCache()
        cache["a"] = .init(name: "a.jpg", type: "public.jpeg")
        cache["b"] = .init(name: "b.jpg", type: "public.jpeg")
        cache.keepOnly(["b", "z"])
        #expect(cache["a"] == nil)
        #expect(cache["b"]?.name == "b.jpg")
        #expect(cache.entries.count == 1)
    }
}
