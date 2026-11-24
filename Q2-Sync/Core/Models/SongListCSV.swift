//
//  SongListCSV.swift
//  Q2-Sync › Core › Models
//
//  PURPOSE
//  Turns a list of songs into CSV text for Excel or Numbers: what's on the
//  Q2 (as of Q2 Sync's record of the card) and what the next sync will copy.
//
//  HOW IT FITS
//  Pure text building, no files or UI. The File menu's "Export Song List…"
//  asks the library and the Q2's record for the rows, then saves the text
//  where the user picks.
//

import Foundation

enum SongListCSV {

    /// Column titles, in order.
    static let header = ["Status", "Title", "Artist", "Album Artist", "Album", "Genre", "Year",
                         "Disc", "Track", "Duration", "Size (MB)", "Format"]

    /// Builds the CSV.
    ///
    /// - Parameters:
    ///   - snapshot: The library the songs come from.
    ///   - marks: Says where each song stands on the Q2.
    /// - Returns: CSV text (rows end in CRLF, text is quoted when needed),
    ///   with songs on the Q2 or chosen for it, sorted like the Q2 lists them.
    static func make(snapshot: LibrarySnapshot, marks: LibraryMarks) -> String {
        var rows = [header]
        let wanted = snapshot.tracks.compactMap { track -> (Track, String)? in
            switch marks.placement(of: track.id) {
            case .onQ2:     return (track, "On Q2")
            case .nextSync: return (track, "Next sync")
            default:        return nil
            }
        }
        let sorted = wanted.sorted { lhs, rhs in
            let (a, b) = (lhs.0, rhs.0)
            let artist = a.effectiveAlbumArtist.localizedStandardCompare(b.effectiveAlbumArtist)
            if artist != .orderedSame { return artist == .orderedAscending }
            let album = a.displayAlbum.localizedStandardCompare(b.displayAlbum)
            if album != .orderedSame { return album == .orderedAscending }
            if a.discNumber != b.discNumber { return a.discNumber < b.discNumber }
            if a.trackNumber != b.trackNumber { return a.trackNumber < b.trackNumber }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
        for (track, status) in sorted {
            rows.append([
                status, track.title, track.artist ?? "", track.effectiveAlbumArtist, track.album ?? "",
                track.genre ?? "", track.year.map(String.init) ?? "",
                track.discNumber > 0 ? String(track.discNumber) : "",
                track.trackNumber > 0 ? String(track.trackNumber) : "",
                duration(track.durationSeconds),
                String(format: "%.1f", Double(track.fileSize) / 1_000_000),
                track.fileKind ?? ""
            ])
        }
        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// "3:45" or "1:02:03".
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Quotes a field when it holds a comma, quote or line break.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
