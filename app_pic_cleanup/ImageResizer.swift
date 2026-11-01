import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downscales and re-encodes images with ImageIO, keeping EXIF/GPS metadata.
nonisolated enum ImageResizer {
    struct Output: Sendable {
        let data: Data
        let pixelWidth: Int
        let pixelHeight: Int
        let fileExtension: String
    }

    enum ResizeError: LocalizedError {
        case unreadable, encodeFailed
        var errorDescription: String? {
            switch self {
            case .unreadable: "The photo's image data couldn't be read."
            case .encodeFailed: "The resized photo couldn't be encoded."
            }
        }
    }

    static func resize(_ data: Data, maxPixelSize: Int, quality: Double) throws -> Output {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { throw ResizeError.unreadable }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longEdge = max(width, height)
        let targetSize = longEdge > 0 ? min(maxPixelSize, longEdge) : maxPixelSize

        // Applies the EXIF orientation, so the output is stored upright.
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: targetSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
        else { throw ResizeError.unreadable }

        // Keep the original metadata (dates, GPS, camera), but fix values that no longer apply.
        var metadata = properties
        metadata.removeValue(forKey: kCGImagePropertyPixelWidth)
        metadata.removeValue(forKey: kCGImagePropertyPixelHeight)
        metadata[kCGImagePropertyOrientation] = 1
        if var tiff = metadata[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            metadata[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = metadata[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = image.width
            exif[kCGImagePropertyExifPixelYDimension] = image.height
            metadata[kCGImagePropertyExifDictionary] = exif
        }
        metadata[kCGImageDestinationLossyCompressionQuality] = quality

        // Always JPEG (HEIC sources included) so copies open anywhere.
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw ResizeError.encodeFailed }
        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ResizeError.encodeFailed }
        return Output(data: output as Data, pixelWidth: image.width, pixelHeight: image.height, fileExtension: "jpg")
    }

    /// Memory-friendly decode for on-screen display.
    static func downsample(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
