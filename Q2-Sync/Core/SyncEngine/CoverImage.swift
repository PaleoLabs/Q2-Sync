//
//  CoverImage.swift
//  Q2-Sync › Core › SyncEngine
//
//  PURPOSE
//  Turns album artwork (any format Apple Music stores: JPEG, PNG, …) into
//  a `cover.jpg` the Q2 decodes cheaply: a BASELINE (not progressive)
//  JPEG in RGB, no bigger than 1000 px on its longest side. See
//  `AlbumCovers` for why.
//
//  Works entirely in memory with Apple's ImageIO and Core Graphics; reads
//  nothing from disk and writes nothing.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Making cover files.
enum CoverImage {

    /// Longest side, in pixels. Under the 1023 px the Q2's JPEG decoder
    /// handles at full scale.
    static let maximumPixels = 1000

    /// JPEG quality (0…1).
    static let quality = 0.85

    /// Converts artwork into a cover JPEG.
    ///
    /// - Parameters:
    ///   - data: The artwork image bytes.
    ///   - maxPixels: Longest side of the result.
    /// - Returns: Baseline RGB JPEG data, or `nil` if the image can't be read.
    static func makeJPEG(from data: Data, maxPixels: Int = maximumPixels) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        // A thumbnail at most `maxPixels` on its longest side (smaller
        // images keep their size), with the photo's rotation applied.
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }

        // Redraw into plain 8-bit sRGB with no alpha, so greyscale, palette,
        // CMYK or transparent artwork all come out as ordinary RGB.
        let width = thumbnail.width, height = thumbnail.height
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)) // behind transparent parts
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let rgb = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString,
                                                                 1, nil) else { return nil }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyJFIFDictionary: [kCGImagePropertyJFIFIsProgressive: false],
        ]
        CGImageDestinationAddImage(destination, rgb, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
