import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import app_pic_cleanup

/// Builds encoded test images in memory, with optional EXIF/GPS metadata.
private enum TestImage {
    static let dateTaken = "2016:03:02 09:10:44"

    /// Left half red, right half blue, plus grain so sizes resemble real photos.
    /// The color split lets tests check that rotation was applied.
    static func make(width: Int, height: Int, type: UTType = .jpeg, quality: Double = 0.95,
                     orientation: Int = 1, metadata: Bool = true) -> Data {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let pixels = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var seed: UInt32 = 42
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 1664525 &+ 1013904223
                let noise = Int(seed >> 27) - 16
                let p = (y * width + x) * 4
                let red = x < width / 2
                pixels[p] = UInt8(clamping: (red ? 220 : 30) + noise)
                pixels[p + 1] = UInt8(clamping: 40 + noise)
                pixels[p + 2] = UInt8(clamping: (red ? 30 : 220) + noise)
                pixels[p + 3] = 255
            }
        }

        var props: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImageDestinationLossyCompressionQuality: quality,
        ]
        if metadata {
            props[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: dateTaken]
            props[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 45.5, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.6, kCGImagePropertyGPSLongitudeRef: "W",
            ]
        }

        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, props as CFDictionary)
        precondition(CGImageDestinationFinalize(dest), "Couldn't encode test image")
        return data as Data
    }

    static func properties(_ data: Data) -> [CFString: Any] {
        let src = CGImageSourceCreateWithData(data as CFData, nil)!
        return CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
    }

    static func type(_ data: Data) -> String? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
    }

    /// Red and blue values of the pixel at the given position (0...1, origin top-left as displayed).
    static func pixel(_ data: Data, x xFraction: Double, y yFraction: Double) -> (r: Int, b: Int) {
        let src = CGImageSourceCreateWithData(data as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = ctx.data!.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        let x = Int(Double(image.width - 1) * xFraction)
        let y = Int(Double(image.height - 1) * yFraction)
        let p = (y * image.width + x) * 4
        return (Int(pixels[p]), Int(pixels[p + 2]))
    }
}

@Suite("Image resizer")
struct ImageResizerTests {
    @Test func scalesLongEdgeAndKeepsAspectRatio() throws {
        let input = TestImage.make(width: 4032, height: 3024)
        let output = try ImageResizer.resize(input, maxPixelSize: 2048, quality: 0.7)
        #expect(output.pixelWidth == 2048)
        #expect(output.pixelHeight == 1536)
        #expect(output.data.count < input.count)
    }

    @Test func neverUpscalesSmallPhotos() throws {
        let output = try ImageResizer.resize(TestImage.make(width: 1024, height: 768), maxPixelSize: 2048, quality: 0.7)
        #expect(output.pixelWidth == 1024)
        #expect(output.pixelHeight == 768)
    }

    @Test(arguments: [UTType.jpeg, UTType.heic])
    func alwaysOutputsJPEG(inputType: UTType) throws {
        let output = try ImageResizer.resize(TestImage.make(width: 1600, height: 1200, type: inputType), maxPixelSize: 1024, quality: 0.7)
        #expect(output.fileExtension == "jpg")
        #expect(TestImage.type(output.data) == UTType.jpeg.identifier)
    }

    @Test func keepsDateTakenAndLocation() throws {
        let output = try ImageResizer.resize(TestImage.make(width: 1600, height: 1200), maxPixelSize: 1024, quality: 0.7)
        let props = TestImage.properties(output.data)
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] as? String == TestImage.dateTaken)
        #expect(abs((gps?[kCGImagePropertyGPSLatitude] as? Double ?? 0) - 45.5) < 0.001)
        #expect(gps?[kCGImagePropertyGPSLatitudeRef] as? String == "N")
    }

    @Test func updatesExifDimensionsToNewSize() throws {
        let output = try ImageResizer.resize(TestImage.make(width: 1600, height: 1200), maxPixelSize: 800, quality: 0.7)
        let exif = TestImage.properties(output.data)[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifPixelXDimension] as? Int == 800)
        #expect(exif?[kCGImagePropertyExifPixelYDimension] as? Int == 600)
    }

    /// Orientation 6 = camera held upright, pixels stored sideways (common in older JPEGs).
    /// The copy must be stored upright with orientation 1, or it would display rotated.
    @Test func bakesInRotationFromSidewaysPhotos() throws {
        let input = TestImage.make(width: 1600, height: 1200, orientation: 6)
        let output = try ImageResizer.resize(input, maxPixelSize: 800, quality: 0.9)
        #expect(output.pixelWidth == 600)
        #expect(output.pixelHeight == 800)

        let props = TestImage.properties(output.data)
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        let tiffOrientation = (props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFOrientation] as? Int ?? 1
        #expect(orientation == 1)
        #expect(tiffOrientation == 1)

        // Stored pixels: left half red. Orientation 6 rotates 90° clockwise for display,
        // so the upright copy must be red on top and blue on the bottom.
        let top = TestImage.pixel(output.data, x: 0.5, y: 0.1)
        let bottom = TestImage.pixel(output.data, x: 0.5, y: 0.9)
        #expect(top.r > top.b, "Top should be red, got r=\(top.r) b=\(top.b)")
        #expect(bottom.b > bottom.r, "Bottom should be blue, got r=\(bottom.r) b=\(bottom.b)")
    }

    @Test func keepsUprightPhotosUnrotated() throws {
        let output = try ImageResizer.resize(TestImage.make(width: 1600, height: 1200), maxPixelSize: 800, quality: 0.9)
        let left = TestImage.pixel(output.data, x: 0.1, y: 0.5)
        let right = TestImage.pixel(output.data, x: 0.9, y: 0.5)
        #expect(left.r > left.b)
        #expect(right.b > right.r)
    }

    @Test func lowerQualityMakesSmallerFiles() throws {
        let input = TestImage.make(width: 1600, height: 1200)
        let low = try ImageResizer.resize(input, maxPixelSize: 1600, quality: 0.4)
        let high = try ImageResizer.resize(input, maxPixelSize: 1600, quality: 0.95)
        #expect(low.data.count < high.data.count)
    }

    @Test func worksWithoutMetadata() throws {
        let output = try ImageResizer.resize(TestImage.make(width: 1600, height: 1200, metadata: false), maxPixelSize: 800, quality: 0.7)
        #expect(output.pixelWidth == 800)
    }

    @Test func rejectsDataThatIsNotAnImage() {
        #expect(throws: ImageResizer.ResizeError.self) {
            try ImageResizer.resize(Data("definitely not a photo".utf8), maxPixelSize: 2048, quality: 0.7)
        }
    }
}
