import Foundation

/// User-chosen rules for which photos to shrink and how.
nonisolated struct CleanupSettings: Codable, Equatable, Sendable {
    /// Only photos taken before this day are considered.
    var cutoffDate: Date
    /// Only photos larger than this (in megabytes) are considered.
    var minFileSizeMB: Double
    /// Longest side of the resized photo, in pixels.
    var maxPixelSize: Int
    /// JPEG compression quality, 0...1.
    var quality: Double
    /// Live Photos lose their video part when replaced, so they're opt-in.
    var includeLivePhotos: Bool
    /// How many replaced originals to collect before asking iOS to delete them.
    var batchSize: Int

    /// A resized copy must be at most this fraction of the original's size,
    /// otherwise the photo is left alone.
    static let maxSizeRatio = 0.8

    static let pixelSizeOptions = [1280, 1600, 2048, 2560, 3024]

    static let `default` = CleanupSettings(
        cutoffDate: Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now,
        minFileSizeMB: 3,
        maxPixelSize: 2048,
        quality: 0.7,
        includeLivePhotos: false,
        batchSize: 50
    )

    var minFileSizeBytes: Int64 { Int64(minFileSizeMB * 1_000_000) }

    /// Start of the chosen day, so "taken before Jan 1" excludes Jan 1 itself.
    var cutoffStartOfDay: Date { Calendar.current.startOfDay(for: cutoffDate) }

    // MARK: - Rules (pure, unit tested)

    /// Size and Live Photo filters applied during a scan.
    /// The date filter runs inside the PhotoKit query (see `PhotoLibrary.scan`).
    func includes(fileSize: Int64, isLivePhoto: Bool) -> Bool {
        (includeLivePhotos || !isLivePhoto) && fileSize > minFileSizeBytes
    }

    /// Whether a resized copy of `newSize` bytes is worth replacing an original of `originalSize` bytes.
    static func isWorthReplacing(originalSize: Int64, newSize: Int) -> Bool {
        originalSize > 0 && Double(newSize) <= Double(originalSize) * maxSizeRatio
    }

    /// Average new/original size ratio over real samples. Samples that wouldn't be
    /// replaced count as 1 (unchanged). Returns nil when there are no samples.
    static func estimatedRatio(samples: [(originalSize: Int64, newSize: Int)]) -> Double? {
        guard !samples.isEmpty else { return nil }
        let ratios = samples.map { sample in
            isWorthReplacing(originalSize: sample.originalSize, newSize: sample.newSize)
                ? Double(sample.newSize) / Double(sample.originalSize)
                : 1
        }
        return ratios.reduce(0, +) / Double(ratios.count)
    }

    /// Up to `maxSamples` indices spread evenly over `count` items, starting at 0.
    static func sampleIndices(count: Int, maxSamples: Int) -> [Int] {
        guard count > 0, maxSamples > 0 else { return [] }
        let n = min(maxSamples, count)
        let step = Double(count) / Double(n)
        return (0..<n).map { Int(Double($0) * step) }
    }

    // MARK: - Persistence

    private static let defaultsKey = "cleanupSettings"

    static func load() -> CleanupSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(CleanupSettings.self, from: data)
        else { return .default }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// A photo that matches the current settings.
nonisolated struct Candidate: Identifiable, Hashable, Sendable {
    /// PHAsset local identifier.
    let id: String
    let creationDate: Date?
    /// Total bytes of all stored resources (what deleting the original frees).
    let fileSize: Int64
    let pixelWidth: Int
    let pixelHeight: Int
    let isLivePhoto: Bool

    func resizedDimensions(maxPixelSize: Int) -> (width: Int, height: Int) {
        let longEdge = max(pixelWidth, pixelHeight)
        guard longEdge > maxPixelSize else { return (pixelWidth, pixelHeight) }
        let scale = Double(maxPixelSize) / Double(longEdge)
        return (Int((Double(pixelWidth) * scale).rounded()), Int((Double(pixelHeight) * scale).rounded()))
    }
}

nonisolated func formatBytes(_ bytes: Int64) -> String {
    bytes.formatted(.byteCount(style: .file))
}
