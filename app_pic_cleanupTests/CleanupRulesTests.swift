import Foundation
import Testing
@testable import app_pic_cleanup

@Suite("Scan filters")
struct ScanFilterTests {
    private func settings(minMB: Double = 3, includeLive: Bool = false) -> CleanupSettings {
        var s = CleanupSettings.default
        s.minFileSizeMB = minMB
        s.includeLivePhotos = includeLive
        return s
    }

    @Test func minFileSizeIsInDecimalMegabytes() {
        #expect(settings(minMB: 3).minFileSizeBytes == 3_000_000)
        #expect(settings(minMB: 1.5).minFileSizeBytes == 1_500_000)
    }

    @Test func includesOnlyPhotosStrictlyLargerThanThreshold() {
        let s = settings(minMB: 3)
        #expect(s.includes(fileSize: 3_000_001, isLivePhoto: false))
        #expect(!s.includes(fileSize: 3_000_000, isLivePhoto: false))
        #expect(!s.includes(fileSize: 200_000, isLivePhoto: false))
    }

    @Test func livePhotosExcludedUnlessOptedIn() {
        #expect(!settings(includeLive: false).includes(fileSize: 10_000_000, isLivePhoto: true))
        #expect(settings(includeLive: true).includes(fileSize: 10_000_000, isLivePhoto: true))
    }

    @Test func livePhotosStillNeedToBeLargeEnough() {
        #expect(!settings(minMB: 3, includeLive: true).includes(fileSize: 1_000_000, isLivePhoto: true))
    }

    @Test func cutoffIsStartOfChosenDay() throws {
        var s = CleanupSettings.default
        let calendar = Calendar.current
        let afternoon = try #require(calendar.date(from: DateComponents(year: 2020, month: 1, day: 15, hour: 16, minute: 30)))
        s.cutoffDate = afternoon
        let expected = try #require(calendar.date(from: DateComponents(year: 2020, month: 1, day: 15)))
        // "Taken before Jan 15" must not include photos from the morning of Jan 15.
        #expect(s.cutoffStartOfDay == expected)
    }
}

@Suite("Replace decision")
struct ReplaceDecisionTests {
    @Test(arguments: [
        (original: Int64(1_000_000), new: 800_000, expected: true),   // exactly 20% smaller
        (original: Int64(1_000_000), new: 800_001, expected: false),  // just under 20%
        (original: Int64(5_000_000), new: 500_000, expected: true),
        (original: Int64(1_000_000), new: 1_200_000, expected: false), // copy is bigger
        (original: Int64(0), new: 0, expected: false),                 // unknown original size
    ])
    func worthReplacing(original: Int64, new: Int, expected: Bool) {
        #expect(CleanupSettings.isWorthReplacing(originalSize: original, newSize: new) == expected)
    }
}

@Suite("Savings estimate")
struct SavingsEstimateTests {
    @Test func noSamplesMeansNoEstimate() {
        #expect(CleanupSettings.estimatedRatio(samples: []) == nil)
    }

    @Test func averagesRatiosOfReplaceableSamples() throws {
        let ratio = try #require(CleanupSettings.estimatedRatio(samples: [
            (originalSize: 1_000_000, newSize: 200_000),
            (originalSize: 1_000_000, newSize: 400_000),
        ]))
        #expect(abs(ratio - 0.3) < 0.0001)
    }

    @Test func skippedSamplesCountAsUnchanged() throws {
        let ratio = try #require(CleanupSettings.estimatedRatio(samples: [
            (originalSize: 1_000_000, newSize: 200_000), // 0.2
            (originalSize: 1_000_000, newSize: 950_000), // would be skipped -> 1.0
        ]))
        #expect(abs(ratio - 0.6) < 0.0001)
    }

    @Test func sampleIndicesSpreadAcrossList() {
        #expect(CleanupSettings.sampleIndices(count: 60, maxSamples: 6) == [0, 10, 20, 30, 40, 50])
    }

    @Test func sampleIndicesNeverExceedCount() {
        #expect(CleanupSettings.sampleIndices(count: 3, maxSamples: 6) == [0, 1, 2])
        #expect(CleanupSettings.sampleIndices(count: 0, maxSamples: 6).isEmpty)
        #expect(CleanupSettings.sampleIndices(count: 7, maxSamples: 6).allSatisfy { $0 < 7 })
    }
}

@Suite("Resized dimensions")
struct ResizedDimensionsTests {
    private func candidate(_ w: Int, _ h: Int) -> Candidate {
        Candidate(id: "x", creationDate: nil, fileSize: 1, pixelWidth: w, pixelHeight: h, isLivePhoto: false)
    }

    @Test func landscapeScalesLongEdge() {
        let d = candidate(4032, 3024).resizedDimensions(maxPixelSize: 2048)
        #expect(d.width == 2048 && d.height == 1536)
    }

    @Test func portraitScalesLongEdge() {
        let d = candidate(3024, 4032).resizedDimensions(maxPixelSize: 2048)
        #expect(d.width == 1536 && d.height == 2048)
    }

    @Test func smallerPhotosAreNeverUpscaled() {
        let d = candidate(1024, 768).resizedDimensions(maxPixelSize: 2048)
        #expect(d.width == 1024 && d.height == 768)
    }
}

@Suite("Settings persistence")
struct SettingsPersistenceTests {
    @Test func roundTripsThroughJSON() throws {
        var s = CleanupSettings.default
        s.minFileSizeMB = 1.5
        s.maxPixelSize = 3024
        s.quality = 0.85
        s.includeLivePhotos = true
        s.batchSize = 120
        let decoded = try JSONDecoder().decode(CleanupSettings.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
    }

    @Test func defaultPixelSizeIsOneOfThePickerOptions() {
        #expect(CleanupSettings.pixelSizeOptions.contains(CleanupSettings.default.maxPixelSize))
    }
}
