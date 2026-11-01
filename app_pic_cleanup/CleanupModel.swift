import Foundation
import Observation
import Photos
import UIKit

@Observable
final class CleanupModel {
    enum RunState { case idle, running, stopping }

    var settings: CleanupSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            // Old preview no longer reflects the settings.
            candidates = nil
            estimatedRatio = nil
        }
    }

    private(set) var authorization = PhotoLibrary.authorizationStatus

    // Preview
    private(set) var candidates: [Candidate]?
    private(set) var isScanning = false
    private(set) var scanProgress = 0.0
    /// Average resized size / original size, measured on real samples.
    private(set) var estimatedRatio: Double?
    private(set) var isEstimating = false

    // Run
    private(set) var runState = RunState.idle
    private(set) var runTotal = 0
    private(set) var runDone = 0
    private(set) var runReplaced = 0
    private(set) var runSkipped = 0
    private(set) var runFailed = 0
    private(set) var runBytesSaved: Int64 = 0
    private(set) var statusMessage: String?

    private(set) var journal = Journal.load()
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    init() {
        settings = .load()
    }

    var totalOriginalBytes: Int64 {
        candidates?.reduce(0) { $0 + $1.fileSize } ?? 0
    }

    var estimatedNewBytes: Int64? {
        estimatedRatio.map { Int64(Double(totalOriginalBytes) * $0) }
    }

    func estimatedSize(of candidate: Candidate) -> Int64? {
        estimatedRatio.map { Int64(Double(candidate.fileSize) * $0) }
    }

    func requestAccess() async {
        authorization = await PhotoLibrary.requestAccess()
    }

    // MARK: - Preview

    func scan() async {
        guard !isScanning, runState == .idle else { return }
        isScanning = true
        scanProgress = 0
        estimatedRatio = nil
        statusMessage = nil

        let settings = self.settings
        let excluded = journal.excludedIDs
        let result = await Task.detached(priority: .userInitiated) {
            PhotoLibrary.scan(settings: settings, excluding: excluded) { done, total in
                Task { @MainActor in
                    self.scanProgress = total > 0 ? Double(done) / Double(total) : 1
                }
            }
        }.value

        isScanning = false
        // Ignore the result if settings changed mid-scan.
        guard settings == self.settings else { return }
        candidates = result
        await estimateSavings()
    }

    /// Resizes a handful of photos spread across the list to measure real savings.
    private func estimateSavings() async {
        guard let candidates, !candidates.isEmpty else { return }
        isEstimating = true
        defer { isEstimating = false }

        var measured: [(originalSize: Int64, newSize: Int)] = []
        for index in CleanupSettings.sampleIndices(count: candidates.count, maxSamples: 6) {
            let sample = candidates[index]
            guard let output = try? await resize(sample) else { continue }
            measured.append((sample.fileSize, output.data.count))
        }

        guard self.candidates == candidates else { return }
        estimatedRatio = CleanupSettings.estimatedRatio(samples: measured)
    }

    func resize(_ candidate: Candidate) async throws -> ImageResizer.Output {
        let data = try await PhotoLibrary.loadImageData(id: candidate.id)
        let maxPixelSize = settings.maxPixelSize
        let quality = settings.quality
        return try await Task.detached(priority: .userInitiated) {
            try ImageResizer.resize(data, maxPixelSize: maxPixelSize, quality: quality)
        }.value
    }

    // MARK: - Run

    func startRun() {
        guard runState == .idle, let queue = candidates, !queue.isEmpty else { return }
        runState = .running
        runTotal = queue.count
        runDone = 0
        runReplaced = 0
        runSkipped = 0
        runFailed = 0
        runBytesSaved = 0
        statusMessage = nil

        // Keep the screen on, and ask for a little extra time if the user switches apps.
        UIApplication.shared.isIdleTimerDisabled = true
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PhotoCleanup") { [weak self] in
            self?.endBackgroundTask()
        }

        Task { await run(queue) }
    }

    /// Finishes the current photo, then stops.
    func stopRun() {
        if runState == .running { runState = .stopping }
    }

    private func run(_ queue: [Candidate]) async {
        var pausedForDeletion = false

        for candidate in queue {
            guard runState == .running else { break }
            await process(candidate)
            runDone += 1

            if journal.pendingDeletion.count >= settings.batchSize {
                guard await deletePendingOriginals() else {
                    pausedForDeletion = true
                    break
                }
            }
        }

        if !pausedForDeletion && !journal.pendingDeletion.isEmpty {
            pausedForDeletion = !(await deletePendingOriginals())
        }

        let excluded = journal.excludedIDs
        candidates = candidates?.filter { !excluded.contains($0.id) }

        if statusMessage == nil {
            if pausedForDeletion {
                statusMessage = "Stopped: the deletion wasn't approved. The smaller copies are saved, and the originals are still on your phone. Tap “Delete replaced originals” to try again."
            } else {
                statusMessage = runState == .stopping ? "Stopped." : "Done."
            }
        }

        UIApplication.shared.isIdleTimerDisabled = false
        endBackgroundTask()
        runState = .idle
    }

    private func process(_ candidate: Candidate) async {
        do {
            let output = try await resize(candidate)

            guard CleanupSettings.isWorthReplacing(originalSize: candidate.fileSize, newSize: output.data.count) else {
                journal.skipped[candidate.id] = "The resized copy wouldn't be meaningfully smaller."
                journal.save()
                runSkipped += 1
                return
            }

            let url = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString + "." + output.fileExtension)
            try output.data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            let newID = try await PhotoLibrary.saveReplacement(
                fileURL: url,
                fileExtension: output.fileExtension,
                replacing: candidate.id
            )

            // Record immediately so a crash never orphans an original without its copy.
            journal.replacements[candidate.id] = newID
            journal.pendingDeletion.append(candidate.id)
            journal.save()
            runReplaced += 1
            runBytesSaved += candidate.fileSize - Int64(output.data.count)
        } catch {
            // Not recorded in the journal, so a later scan picks it up again.
            runFailed += 1
            print("Failed to process \(candidate.id): \(error)")
        }
    }

    /// Asks iOS to delete originals that already have smaller copies. Returns false if not approved.
    @discardableResult
    func deletePendingOriginals() async -> Bool {
        let ids = journal.pendingDeletion
        guard !ids.isEmpty else { return true }
        do {
            guard try await PhotoLibrary.deleteAssets(ids: ids) else { return false }
            let deleted = Set(ids)
            journal.pendingDeletion.removeAll { deleted.contains($0) }
            journal.save()
            return true
        } catch {
            statusMessage = "Couldn't delete the originals: \(error.localizedDescription)"
            return false
        }
    }

    func forgetSkipped() {
        journal.skipped = [:]
        journal.save()
        candidates = nil
        estimatedRatio = nil
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
