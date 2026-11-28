//
//  PhotoSelection.swift
//  Q2-Sync › Core › Models
//
//  PURPOSE
//  What a Q2's Photos tab is set to (issue #68), like Finder's iPod Photos
//  page: "Sync photos onto [Q2]" on or off, where the photos come from,
//  "All photos and albums" or "Selected albums", "Only favorites",
//  "Automatically include photos from" a recent period, and "Include
//  full-resolution photos".
//
//  HOW IT FITS
//  Saved per Q2 in `KnownDevice.photos` and part of `DeviceSyncSettings`,
//  so Revert and Apply cover it. Albums are remembered by `PhotoAlbum.id`
//  (PhotoKit's local identifier). Which photo lands in which card folder
//  is the planner's job; this type only holds the choices.
//

import Foundation

/// Where a Q2's photos come from.
enum PhotoSyncSource: Codable, Hashable, Sendable {

    /// The Mac's Photos library, read through PhotoKit.
    case photosLibrary

    /// A folder the user chose, remembered by a security-scoped bookmark.
    /// Not built yet: stored now so settings saved later still load here.
    case folder(bookmark: Data)
}

/// "Automatically include photos from": a recent period whose photos come
/// along under "Selected albums", whatever album they're in.
enum PhotoRecentWindow: String, Codable, CaseIterable, Hashable, Sendable {
    case lastWeek
    case lastMonth
    case last2Months
    case last3Months
    case last6Months
    case lastYear

    /// The menu's wording.
    var title: String {
        switch self {
        case .lastWeek: return "the last week"
        case .lastMonth: return "the last month"
        case .last2Months: return "the last 2 months"
        case .last3Months: return "the last 3 months"
        case .last6Months: return "the last 6 months"
        case .lastYear: return "the last year"
        }
    }

    /// The earliest creation date that counts as recent.
    ///
    /// - Parameters:
    ///   - now: The moment to count back from (the sync's start).
    ///   - calendar: The calendar to count months in (the user's).
    /// - Returns: `now` minus the period.
    func startDate(before now: Date, calendar: Calendar = .current) -> Date {
        let (component, value): (Calendar.Component, Int) = switch self {
        case .lastWeek: (.day, -7)
        case .lastMonth: (.month, -1)
        case .last2Months: (.month, -2)
        case .last3Months: (.month, -3)
        case .last6Months: (.month, -6)
        case .lastYear: (.year, -1)
        }
        return calendar.date(byAdding: component, value: value, to: now) ?? now
    }
}

/// The Photos tab's settings for one Q2.
struct PhotoSelection: Codable, Hashable, Sendable {

    /// "Sync photos onto [Q2]". Off by default.
    var isEnabled = false

    /// Where the photos come from. Only the Photos library for now.
    var source: PhotoSyncSource = .photosLibrary

    /// `true`: "All photos and albums" (every user album, plus photos in no
    /// album). `false`: "Selected albums", only those in `albumIDs`.
    var includesAll = true

    /// The ticked albums when `includesAll` is off. Kept while "All" is on,
    /// so switching back to "Selected" brings the ticks back.
    var albumIDs: Set<String> = []

    /// "Only favorites": skip photos that aren't marked as favourites.
    /// With "Selected albums", the favourites within the ticked albums.
    var onlyFavorites = false

    /// "Automatically include photos from": `nil` is "no photos". Only
    /// used under "Selected albums" (greyed out under "All").
    var recentWindow: PhotoRecentWindow? = nil

    /// "Include full-resolution photos": copy the originals (as JPEG)
    /// instead of screen-size copies. Off by default.
    var fullResolution = false

    init(isEnabled: Bool = false, source: PhotoSyncSource = .photosLibrary, includesAll: Bool = true,
         albumIDs: Set<String> = [], onlyFavorites: Bool = false,
         recentWindow: PhotoRecentWindow? = nil, fullResolution: Bool = false) {
        self.isEnabled = isEnabled
        self.source = source
        self.includesAll = includesAll
        self.albumIDs = albumIDs
        self.onlyFavorites = onlyFavorites
        self.recentWindow = recentWindow
        self.fullResolution = fullResolution
    }

    /// `true` if the album's tick box shows ticked. Under "All", every
    /// album that "All" brings is ticked; Hidden and the smart albums
    /// never are (they'd only repeat photos, or show hidden ones).
    func isTicked(_ album: PhotoAlbum) -> Bool {
        includesAll ? album.kind.isIncludedByAll : albumIDs.contains(album.id)
    }

    /// The recent period that applies: `nil` under "All", which brings
    /// every photo anyway.
    var effectiveRecentWindow: PhotoRecentWindow? { includesAll ? nil : recentWindow }

    /// Ticks or unticks albums under "Selected". Ignored under "All".
    mutating func setTicked(_ ticked: Bool, ids: Set<String>) {
        guard !includesAll else { return }
        if ticked { albumIDs.formUnion(ids) } else { albumIDs.subtract(ids) }
    }

    // Missing keys decode to their defaults, so later additions don't
    // break settings saved by this version.
    private enum CodingKeys: String, CodingKey {
        case isEnabled, source, includesAll, albumIDs, onlyFavorites, recentWindow, fullResolution
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        // A source a later version added falls back to the Photos library
        // rather than losing every other setting.
        source = (try? c.decodeIfPresent(PhotoSyncSource.self, forKey: .source)) ?? .photosLibrary
        includesAll = try c.decodeIfPresent(Bool.self, forKey: .includesAll) ?? true
        albumIDs = try c.decodeIfPresent(Set<String>.self, forKey: .albumIDs) ?? []
        onlyFavorites = try c.decodeIfPresent(Bool.self, forKey: .onlyFavorites) ?? false
        recentWindow = try? c.decodeIfPresent(PhotoRecentWindow.self, forKey: .recentWindow)
        fullResolution = try c.decodeIfPresent(Bool.self, forKey: .fullResolution) ?? false
    }
}

extension PhotoSelection: ContentSyncChoice {

    /// `true` if photos are off, or on with "Selected albums", no ticks
    /// and no recent period.
    var choosesNothing: Bool {
        !isEnabled || (!includesAll && albumIDs.isEmpty && recentWindow == nil)
    }
}
