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
    /// Files smaller than this are dropped before persisting. A 1 MB threshold
    /// roughly halves the persisted entry count on a typical macOS home and
    /// makes the snapshot save complete in seconds rather than tens of seconds.
    public static let fileSizeThresholdBytes: Int64 = 1024 * 1024

    /// Per-directory cap on persisted file entries. Caps blow-up cases like
    /// huge `node_modules` trees while leaving typical folders untouched.
    public static let perParentFileCap: Int = 100

    public static var url: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return support
            .appendingPathComponent("Jubako", isDirectory: true)
            .appendingPathComponent("snapshot.plist")
    }

    private static let inFlightLock = NSLock()
    private static var inFlightCount: Int = 0

    /// True while at least one save is running; used by AppDelegate to delay
    /// app termination until persistence finishes.
    public static var hasPendingSave: Bool {
        inFlightLock.lock()
        defer { inFlightLock.unlock() }
        return inFlightCount > 0
    }

    /// Synchronous; expected to be called from a background task.
    public static func save(_ snapshot: ScanSnapshot) {
        inFlightLock.lock()
        inFlightCount += 1
        inFlightLock.unlock()
        defer {
            inFlightLock.lock()
            inFlightCount -= 1
            inFlightLock.unlock()
        }

        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
            NSLog("Jubako: snapshot saved (%d bytes) at %@", data.count, url.path)
        } catch {
            NSLog("Jubako: snapshot save failed: %@", error.localizedDescription)
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

    /// Drop small files and cap each parent's file count. All directories
    /// are kept so drilldown navigation works identically.
    public static func prune(_ byParent: [String: [ScanEntry]]) -> [String: [ScanEntry]] {
        var result: [String: [ScanEntry]] = [:]
        result.reserveCapacity(byParent.count)
        for (parent, entries) in byParent {
            var dirs: [ScanEntry] = []
            var files: [ScanEntry] = []
            dirs.reserveCapacity(entries.count)
            files.reserveCapacity(entries.count)
            for e in entries {
                if e.isDirectory {
                    dirs.append(e)
                } else if e.size >= fileSizeThresholdBytes {
                    files.append(e)
                }
            }
            if files.count > perParentFileCap {
                files.sort { $0.size > $1.size }
                files = Array(files.prefix(perParentFileCap))
            }
            result[parent] = dirs + files
        }
        return result
    }
}
