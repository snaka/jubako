import Foundation

public struct ScanSnapshot: Codable, Sendable {
    public let scannedAt: Date
    public let rootPath: String
    public let totalFiles: Int
    public let totalBytes: Int64
    public let elapsed: TimeInterval
    public let errorCount: Int
    public let lastError: String
    public let deferredPaths: [String]
    public let entriesByParent: [String: [ScanEntry]]
}

public enum SnapshotStore {
    /// File size threshold below which files are dropped before persisting.
    /// Drilldown still shows directories (via per-dir aggregates), so the cost
    /// of pruning small files is just hiding them in the per-folder file list,
    /// which is acceptable for "find big stuff" use cases.
    public static let fileSizeThresholdBytes: Int64 = 100 * 1024

    public static var url: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return support
            .appendingPathComponent("Jubako", isDirectory: true)
            .appendingPathComponent("snapshot.plist")
    }

    /// Synchronous; expected to be called from a background task.
    public static func save(_ snapshot: ScanSnapshot) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            // Don't fail the scan on a persistence error; just log to stderr.
            FileHandle.standardError.write(Data("snapshot save failed: \(error)\n".utf8))
        }
    }

    public static func load() -> ScanSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try PropertyListDecoder().decode(ScanSnapshot.self, from: data)
        } catch {
            // Corrupt or version-incompatible snapshot. Delete it so we don't
            // keep failing on subsequent launches.
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    public static func delete() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Drop files below the size threshold; keep all directories intact so
    /// drilldown navigation works the same.
    public static func prune(_ byParent: [String: [ScanEntry]]) -> [String: [ScanEntry]] {
        var result: [String: [ScanEntry]] = [:]
        result.reserveCapacity(byParent.count)
        for (parent, entries) in byParent {
            result[parent] = entries.filter { $0.isDirectory || $0.size >= fileSizeThresholdBytes }
        }
        return result
    }
}
