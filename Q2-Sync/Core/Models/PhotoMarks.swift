//
//  PhotoMarks.swift
//  Q2-Sync › Core › Models
//
//  PURPOSE
//  Where each photo stands relative to a Q2, for the sidebar's Photos ›
//  Albums browser: on the Q2, copied at the next sync, or not chosen. The
//  photo counterpart of `PodcastMarks`. Also says when the sidebar's
//  Photos section shows (#68).
//
//  HOW IT FITS
//  Built by `PhotoBrowserView` from the Photos library, the Mac-side
//  record of the card (`CardContentsRecord.photoAssetIDs`) and the Q2's
//  saved photo settings, using `PhotoPlanner.wantedKeys` so "next sync"
//  means exactly what the sync would copy. Read-only: nothing here plans
//  a sync.
//
//  A photo is marked once, whichever album it's shown in: a photo in two
//  albums is on the Q2 if either copy is.
//

import Foundation

/// Photo marks for the Albums browser.
struct PhotoMarks: Sendable, Equatable {

    /// Photos on the Q2, or `nil` when there's no record of its photos
    /// (no Q2 read yet, or a record saved before photos were recorded).
    let onQ2IDs: Set<String>?

    /// Photos the Q2's settings would copy, or `nil` when that isn't known
    /// (no Q2, or a source other than the Photos library).
    let wantedIDs: Set<String>?

    /// `true` when there's a Q2's photos to compare with.
    var hasQ2: Bool { onQ2IDs != nil }

    /// Builds the marks.
    ///
    /// - Parameters:
    ///   - record: The Q2's last known contents, if any.
    ///   - selection: Its saved photo settings, if any.
    ///   - library: The Photos library as read.
    ///   - now: The time "recent" photos are counted back from.
    init(record: CardContentsRecord?, selection: PhotoSelection?, library: PhotoLibraryContents,
         now: Date = .now) {
        onQ2IDs = record?.photoAssetIDs
        if onQ2IDs != nil, let selection,
           let wanted = PhotoPlanner.wantedKeys(library: library, selection: selection, now: now) {
            wantedIDs = Set(wanted.values.map(\.id))
        } else {
            wantedIDs = nil
        }
    }

    /// Where one photo stands, or `nil` when there's no Q2 to compare with.
    func placement(of asset: PhotoAsset) -> TrackPlacement? {
        guard let onQ2IDs else { return nil }
        if onQ2IDs.contains(asset.id) { return .onQ2 }
        return wantedIDs?.contains(asset.id) == true ? .nextSync : .notChosen
    }

    /// How many of these photos are on the Q2, or `nil` without a Q2.
    func onQ2Count(of assets: [PhotoAsset]) -> Int? {
        guard let onQ2IDs else { return nil }
        return assets.count { onQ2IDs.contains($0.id) }
    }
}

extension Sequence where Element == KnownDevice {

    /// `true` when any of these Q2s syncs photos. The sidebar shows its
    /// Photos section then, like Audiobooks and Podcasts (#70).
    var anySyncsPhotos: Bool {
        contains { $0.effectivePhotos.isEnabled }
    }
}
