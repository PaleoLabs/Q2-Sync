//
//  FinderReveal.swift
//  Q2-Sync › Core › Library
//
//  PURPOSE
//  Decides what "Show in Finder" selects for a whole artist, album, genre
//  or playlist, without opening a pile of Finder windows.
//
//  HOW IT FITS
//  Used by the library browser's group list. Works on file paths only; it
//  doesn't touch the files.
//

import Foundation

/// What Finder can show for a group of songs.
enum FinderReveal {

    /// The items to select so one Finder window shows the whole group.
    ///
    /// - Parameter files: The group's song files.
    /// - Returns: The files themselves if they share a folder (an album);
    ///   their folders if those share one (an artist's albums); otherwise
    ///   `nil`, as for most genres and playlists.
    static func items(for files: [URL]) -> [URL]? {
        guard !files.isEmpty else { return nil }
        let folders = Set(files.map { $0.deletingLastPathComponent().standardizedFileURL })
        if folders.count == 1 { return files }
        let parents = Set(folders.map { $0.deletingLastPathComponent().standardizedFileURL })
        guard parents.count == 1 else { return nil }
        return folders.sorted { $0.path < $1.path }
    }
}
