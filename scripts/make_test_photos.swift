// Generates realistic test photos (with EXIF dates/GPS) for the iOS Simulator.
//
// Usage:
//   swift scripts/make_test_photos.swift <output-dir>
//   xcrun simctl addmedia booted <output-dir>/*
//
// Source images come from macOS desktop wallpapers. Grain is added so file sizes
// resemble real camera photos (smooth wallpapers compress unrealistically well).

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Spec {
    let name: String
    let date: String          // EXIF format "yyyy:MM:dd HH:mm:ss"
    let width: Int
    let height: Int
    let type: UTType
    let quality: Double
    let orientation: Int      // EXIF orientation; 6 = shot in portrait, stored sideways
}

let specs: [Spec] = [
    // Old, large: should be picked up with default settings.
    Spec(name: "2014_beach",     date: "2014:07:12 15:21:04", width: 3264, height: 2448, type: .jpeg, quality: 0.95, orientation: 1),
    Spec(name: "2016_mountains", date: "2016:03:02 09:10:44", width: 4032, height: 3024, type: .jpeg, quality: 0.95, orientation: 1),
    Spec(name: "2017_portrait",  date: "2017:11:23 18:45:00", width: 4032, height: 3024, type: .jpeg, quality: 0.95, orientation: 6),
    Spec(name: "2018_city",      date: "2018:05:30 12:00:00", width: 4032, height: 3024, type: .jpeg, quality: 0.92, orientation: 1),
    Spec(name: "2019_heic",      date: "2019:08:14 17:30:10", width: 4032, height: 3024, type: .heic, quality: 0.9,  orientation: 1),
    Spec(name: "2021_heic_48mp", date: "2021:12:24 20:05:33", width: 8064, height: 6048, type: .heic, quality: 0.85, orientation: 1),
    Spec(name: "2022_park",      date: "2022:04:09 11:11:11", width: 4032, height: 3024, type: .jpeg, quality: 0.93, orientation: 1),
    // Old but small: should be excluded by the size filter.
    Spec(name: "2015_small",     date: "2015:01:01 10:00:00", width: 1024, height: 768,  type: .jpeg, quality: 0.6,  orientation: 1),
    // Old, already compact HEIC: likely skipped (JPEG copy wouldn't be 20% smaller).
    Spec(name: "2020_compact",   date: "2020:06:06 06:06:06", width: 2048, height: 1536, type: .heic, quality: 0.5,  orientation: 1),
    // Recent: should be excluded by the date filter.
    Spec(name: "recent",         date: recentDate(), width: 4032, height: 3024, type: .jpeg, quality: 0.95, orientation: 1),
]

func recentDate() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy:MM:dd HH:mm:ss"
    return f.string(from: Date().addingTimeInterval(-7 * 86400))
}

func loadSources() -> [CGImage] {
    let dir = URL(fileURLWithPath: "/System/Library/Desktop Pictures")
    let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    return files
        .filter { ["heic", "jpg", "png"].contains($0.pathExtension.lowercased()) }
        .sorted { $0.path < $1.path }
        .compactMap { url in
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
}

/// Draws `source` filling `width`×`height`, then adds grain like a camera sensor.
func render(_ source: CGImage, width: Int, height: Int, seed: UInt64) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = max(Double(width) / Double(source.width), Double(height) / Double(source.height))
    let w = Double(source.width) * scale, h = Double(source.height) * scale
    ctx.interpolationQuality = .high
    ctx.draw(source, in: CGRect(x: (Double(width) - w) / 2, y: (Double(height) - h) / 2, width: w, height: h))

    let pixels = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
    var state = seed &+ 0x9E3779B97F4A7C15
    for i in 0..<(width * height) {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let noise = Int((state >> 33) % 25) - 12
        for c in 0..<3 {
            let p = i * 4 + c
            pixels[p] = UInt8(clamping: Int(pixels[p]) + noise)
        }
    }
    return ctx.makeImage()!
}

/// Rotates the pixels so that applying `orientation` 6 displays them upright again.
func storedSideways(_ image: CGImage) -> CGImage {
    let ctx = CGContext(data: nil, width: image.height, height: image.width, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(image.width))
    ctx.rotate(by: -.pi / 2)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return ctx.makeImage()!
}

guard CommandLine.arguments.count == 2 else {
    print("Usage: swift make_test_photos.swift <output-dir>")
    exit(1)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let sources = loadSources()
guard !sources.isEmpty else { print("No wallpapers found to use as sources."); exit(1) }

for (index, spec) in specs.enumerated() {
    // Portrait shots: render upright as portrait, then store sideways with orientation 6.
    let portrait = spec.orientation == 6
    var image = render(sources[index % sources.count],
                       width: portrait ? spec.height : spec.width,
                       height: portrait ? spec.width : spec.height,
                       seed: UInt64(index))
    if portrait { image = storedSideways(image) }

    let metadata: [CFString: Any] = [
        kCGImagePropertyOrientation: spec.orientation,
        kCGImageDestinationLossyCompressionQuality: spec.quality,
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifDateTimeOriginal: spec.date,
            kCGImagePropertyExifDateTimeDigitized: spec.date,
        ],
        kCGImagePropertyTIFFDictionary: [
            kCGImagePropertyTIFFDateTime: spec.date,
            kCGImagePropertyTIFFMake: "Apple",
            kCGImagePropertyTIFFModel: "Test Camera",
            kCGImagePropertyTIFFOrientation: spec.orientation,
        ],
        kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 45.5152, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 122.6784, kCGImagePropertyGPSLongitudeRef: "W",
        ],
    ]

    let ext = spec.type == .heic ? "heic" : "jpg"
    let url = outDir.appendingPathComponent("\(spec.name).\(ext)")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, spec.type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, metadata as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { print("Failed: \(url.lastPathComponent)"); continue }

    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print(String(format: "%-22@ %@  %5.1f MB  %dx%d", url.lastPathComponent as NSString, spec.date, Double(size) / 1_000_000, spec.width, spec.height))
}
