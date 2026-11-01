import Foundation

/// Persistent record of work done, so long runs can stop and resume safely.
nonisolated struct Journal: Codable, Sendable {
    /// Original asset ID -> ID of the smaller copy that replaced it.
    var replacements: [String: String] = [:]
    /// Originals that already have a smaller copy but haven't been deleted yet.
    var pendingDeletion: [String] = []
    /// Asset ID -> reason it was left alone.
    var skipped: [String: String] = [:]

    /// Assets a scan should ignore: already handled originals, our own copies, and skipped photos.
    var excludedIDs: Set<String> {
        Set(replacements.keys).union(replacements.values).union(skipped.keys)
    }

    static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "journal.json")
    }

    /// Returns an empty journal if the file is missing or unreadable.
    static func load(from url: URL = defaultFileURL) -> Journal {
        guard let data = try? Data(contentsOf: url),
              let journal = try? JSONDecoder().decode(Journal.self, from: data)
        else { return Journal() }
        return journal
    }

    func save(to url: URL = defaultFileURL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(self).write(to: url, options: .atomic)
        } catch {
            print("Failed to save journal: \(error)")
        }
    }
}
