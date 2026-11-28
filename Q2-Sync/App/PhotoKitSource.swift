//
//  PhotoKitSource.swift
//  Q2-Sync › App
//
//  PURPOSE
//  Reads the Mac's Photos library with PhotoKit (issue #68): the photos
//  and albums (`PhotoSource`), and each photo's image when a sync writes
//  it to the card (`PhotoRendering`).
//
//  SAFETY
//  Reading only. Nothing here calls `PHPhotoLibrary.performChanges`, the
//  only way PhotoKit changes a library. Photos stored only in iCloud
//  ("Optimize Mac Storage") may be downloaded by PhotoKit to be read,
//  as Finder does; that adds nothing to the library.
//
//  WHAT IS READ
//  • Every photo, hidden ones included (videos are never listed).
//  • Favorites, Recently Added, the photo media types (Selfies, Portrait,
//    Panoramas…) and Hidden.
//  • The user's albums, inside folders too (flattened, with the folder
//    path for listing). Shared albums aren't read: Finder doesn't sync them.
//  PhotoKit offers no People album and no Recently Deleted.
//
//  HOW IT FITS
//  `PhotoLibraryModel.source` makes one while access is allowed.
//  `SyncCoordinator` reads the library at each sync and hands the same
//  value to `SyncExecutor.photoRenderer`, which calls `content(for:)` on its
//  background thread.
//

import AppKit
import Foundation
import Photos

/// The Photos library, read through PhotoKit.
struct PhotoKitSource: PhotoSource, PhotoRendering {

    /// The photo media types listed under Media Types (video ones left out).
    static let mediaTypeSubtypes: [PHAssetCollectionSubtype] = [
        .smartAlbumSelfPortraits, .smartAlbumDepthEffect, .smartAlbumLivePhotos,
        .smartAlbumPanoramas, .smartAlbumLongExposures, .smartAlbumBursts,
        .smartAlbumScreenshots, .smartAlbumAnimated, .smartAlbumRAW,
    ]

    // MARK: - PhotoSource

    func loadPhotos() async throws -> PhotoLibraryContents {
        guard Self.isAllowed else { throw PhotoError.notAllowed }
        return await Self.read()
    }

    func health() -> LibraryHealth {
        PhotoHealthCheck.evaluate(isAllowed: Self.isAllowed)
    }

    /// Access is allowed: fully, or for the photos the user picked.
    private static var isAllowed: Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: true
        default: false
        }
    }

    /// Reads everything, off the main thread (a big library takes a while).
    @concurrent
    private static func read() async -> PhotoLibraryContents {
        let assets = readAssets()
        var albums: [PhotoAlbum] = []
        func smartAlbum(_ subtype: PHAssetCollectionSubtype, kind: PhotoAlbumKind) {
            let found = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
            found.enumerateObjects { collection, _, _ in
                albums.append(album(from: collection, kind: kind, folderPath: []))
            }
        }
        smartAlbum(.smartAlbumFavorites, kind: .favorites)
        smartAlbum(.smartAlbumRecentlyAdded, kind: .recentlyAdded)
        for subtype in mediaTypeSubtypes { smartAlbum(subtype, kind: .mediaType) }
        smartAlbum(.smartAlbumAllHidden, kind: .hidden)
        albums += userAlbums(in: PHCollectionList.fetchTopLevelUserCollections(with: nil), folderPath: [])
        return PhotoLibraryContents(assets: assets, albums: albums)
    }

    /// Fetch options for photos only, hidden ones included.
    private static func photoOptions(sorted: Bool) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        if sorted { options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)] }
        return options
    }

    /// Every photo, oldest first.
    private static func readAssets() -> [PhotoAsset] {
        let found = PHAsset.fetchAssets(with: photoOptions(sorted: true))
        var assets: [PhotoAsset] = []
        assets.reserveCapacity(found.count)
        found.enumerateObjects { asset, _, _ in
            autoreleasepool {
                // The original file's name and type (not an edited render's).
                let resources = PHAssetResource.assetResources(for: asset)
                let original = resources.first { $0.type == .photo } ?? resources.first
                assets.append(PhotoAsset(
                    id: asset.localIdentifier,
                    created: asset.creationDate ?? asset.modificationDate ?? .distantPast,
                    modified: asset.modificationDate,
                    isFavorite: asset.isFavorite,
                    isHidden: asset.isHidden,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    originalFileName: original?.originalFilename,
                    uniformTypeIdentifier: original?.uniformTypeIdentifier))
            }
        }
        return assets
    }

    /// One album and its photos, in the album's own order.
    private static func album(from collection: PHAssetCollection, kind: PhotoAlbumKind,
                              folderPath: [String]) -> PhotoAlbum {
        let found = PHAsset.fetchAssets(in: collection, options: photoOptions(sorted: false))
        var ids: [String] = []
        ids.reserveCapacity(found.count)
        found.enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
        return PhotoAlbum(id: collection.localIdentifier, title: title(collection.localizedTitle),
                          kind: kind, folderPath: folderPath, assetIDs: ids)
    }

    /// The user's albums, walking into folders, in the Photos sidebar's order.
    private static func userAlbums(in list: PHFetchResult<PHCollection>, folderPath: [String]) -> [PhotoAlbum] {
        var albums: [PhotoAlbum] = []
        list.enumerateObjects { collection, _, _ in
            if let assetCollection = collection as? PHAssetCollection {
                guard assetCollection.assetCollectionType == .album,
                      assetCollection.assetCollectionSubtype != .albumCloudShared else { return }
                albums.append(album(from: assetCollection, kind: .user, folderPath: folderPath))
            } else if let folder = collection as? PHCollectionList {
                albums += userAlbums(in: PHCollection.fetchCollections(in: folder, options: nil),
                                     folderPath: folderPath + [title(folder.localizedTitle, fallback: "Folder")])
            }
        }
        return albums
    }

    private static func title(_ title: String?, fallback: String = "Album") -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    // MARK: - PhotoRendering

    /// Called by the executor on its background thread, never the main
    /// thread (PhotoKit's synchronous requests block until done).
    func content(for assetID: String, fullResolution: Bool) -> PhotoImageContent? {
        let fetch = PHFetchOptions()
        fetch.includeHiddenAssets = true
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: fetch).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.version = .current // With the user's edits, like Photos shows it.
        // iCloud-only photos ("Optimize Mac Storage") must be downloaded,
        // even for a screen-size copy: there may be no local version at all.
        options.isNetworkAccessAllowed = true

        let result = ResultBox()
        if fullResolution {
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                result.content = data.map { .data($0) }
            }
        } else {
            options.resizeMode = .exact
            let size = CGSize(width: PhotoImage.screenWidth, height: PhotoImage.screenHeight)
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit,
                                                  options: options) { image, _ in
                result.content = image?.cgImage(forProposedRect: nil, context: nil, hints: nil).map { .image($0) }
            }
        }
        return result.content
    }

    /// A small preview of one photo for the Photo Info panel, from what's
    /// already on this Mac (nothing is downloaded from iCloud), or `nil`.
    static func thumbnail(for assetID: String, side: CGFloat) async -> NSImage? {
        let fetch = PHFetchOptions()
        fetch.includeHiddenAssets = true
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: fetch).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat // One answer, not a quick one then a better one.
        options.version = .current
        options.isNetworkAccessAllowed = false
        let size = CGSize(width: side * 2, height: side * 2)
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit,
                                                  options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Holds a synchronous request's result (set before the request returns).
    private final class ResultBox: @unchecked Sendable {
        var content: PhotoImageContent?
    }
}
