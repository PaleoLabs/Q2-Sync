//
//  PhotoImage.swift
//  Q2-Sync › Core › SyncEngine
//
//  PURPOSE
//  Turns a photo from the Photos library into the JPEG Q2 Sync writes to
//  `Photos/` (issue #68):
//  • Screen-size copy (the default): fits inside 750 × 580, twice the
//    Q2 Pod viewer's 375 × 290, so it stays sharp and opens quickly.
//    About 100 KB. Smaller photos keep their size.
//  • Full resolution ("Include full-resolution photos"): the photo's own
//    size. HEIC and PNG become JPEG too, so a photo's file name never
//    changes when the option does.
//  Either way: a BASELINE JPEG in RGB (Q2 Pod's decoder), quality 0.85,
//  turned the right way up, with NO metadata kept (no location, camera
//  details or orientation tag).
//
//  Works entirely in memory with ImageIO and Core Graphics; reads nothing
//  from disk and writes nothing. The App's `PhotoRendering` supplies the
//  image (encoded bytes, or an image PhotoKit already drew).
//

import CoreGraphics
import Foundation
import ImageIO

/// A photo as the Photos library hands it over.
enum PhotoImageContent {
    /// Encoded image bytes (JPEG, HEIC, PNG…), with any orientation tag.
    case data(Data)
    /// An image already drawn the right way up.
    case image(CGImage)
}

/// Reads photos from the Photos library for writing to the card.
///
/// `SyncExecutor` calls it once per photo, on its background thread.
protocol PhotoRendering: Sendable {
    /// The photo, or `nil` if it can't be read (deleted since planning,
    /// not downloaded from iCloud…).
    ///
    /// - Parameters:
    ///   - assetID: `PhotoAsset.id`.
    ///   - fullResolution: Wanted at its own size; otherwise anything at
    ///     least `PhotoImage.screenWidth` × `screenHeight` will do.
    func content(for assetID: String, fullResolution: Bool) -> PhotoImageContent?
}

/// Making photo files.
enum PhotoImage {

    /// The box a screen-size copy fits in, in pixels.
    static let screenWidth = 750
    static let screenHeight = 580

    /// JPEG quality (0…1).
    static let quality = 0.85

    /// The size a `width` × `height` photo is written at: unchanged at
    /// full resolution or if it already fits, else scaled down to fit
    /// 750 × 580, keeping its shape.
    static func outputSize(width: Int, height: Int, fullResolution: Bool) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (0, 0) }
        if fullResolution { return (width, height) }
        let scale = min(1, Double(screenWidth) / Double(width), Double(screenHeight) / Double(height))
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }

    /// Makes the card file for a photo.
    ///
    /// - Returns: Baseline RGB JPEG data, or `nil` if the image can't be read.
    static func makeJPEG(from content: PhotoImageContent, fullResolution: Bool) -> Data? {
        switch content {
        case .data(let data): makeJPEG(from: data, fullResolution: fullResolution)
        case .image(let image): makeJPEG(from: image, fullResolution: fullResolution)
        }
    }

    /// From encoded bytes: decoded straight at the output size (cheap for
    /// big camera photos), with its orientation tag applied.
    static func makeJPEG(from data: Data, fullResolution: Bool) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        // EXIF orientations 5–8 are turned a quarter: width and height swap.
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        let (upright, uprightHeight) = (5...8).contains(orientation) ? (height, width) : (width, height)
        let size = outputSize(width: upright, height: uprightHeight, fullResolution: fullResolution)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return CoverImage.baselineJPEG(from: image, width: image.width, height: image.height, quality: quality)
    }

    /// From an image PhotoKit already drew the right way up.
    static func makeJPEG(from image: CGImage, fullResolution: Bool) -> Data? {
        let size = outputSize(width: image.width, height: image.height, fullResolution: fullResolution)
        return CoverImage.baselineJPEG(from: image, width: size.width, height: size.height, quality: quality)
    }
}
