import Foundation
import Testing
@testable import app_pic_cleanup

@Suite("Journal")
struct JournalTests {
    /// Unique temp file per test, so tests never touch the app's real journal.
    private let url = FileManager.default.temporaryDirectory
        .appending(path: "JournalTests-\(UUID().uuidString)")
        .appending(path: "journal.json")

    @Test func excludesOriginalsCopiesAndSkippedPhotos() {
        var journal = Journal()
        journal.replacements = ["original-1": "copy-1", "original-2": "copy-2"]
        journal.skipped = ["small-1": "reason"]
        // A rescan must never pick up our own copies, or it would shrink them again.
        #expect(journal.excludedIDs == ["original-1", "original-2", "copy-1", "copy-2", "small-1"])
    }

    @Test func emptyJournalExcludesNothing() {
        #expect(Journal().excludedIDs.isEmpty)
    }

    @Test func savesAndLoads() throws {
        var journal = Journal()
        journal.replacements = ["a": "a-copy"]
        journal.pendingDeletion = ["a"]
        journal.skipped = ["b": "too small"]
        journal.save(to: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let loaded = Journal.load(from: url)
        #expect(loaded.replacements == journal.replacements)
        #expect(loaded.pendingDeletion == journal.pendingDeletion)
        #expect(loaded.skipped == journal.skipped)
    }

    @Test func missingFileLoadsEmptyJournal() {
        let loaded = Journal.load(from: url)
        #expect(loaded.replacements.isEmpty && loaded.pendingDeletion.isEmpty && loaded.skipped.isEmpty)
    }

    @Test func corruptFileLoadsEmptyJournal() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data("not json".utf8).write(to: url)
        #expect(Journal.load(from: url).replacements.isEmpty)
    }
}
