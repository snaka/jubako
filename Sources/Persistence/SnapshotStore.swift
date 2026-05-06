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
        supportDirectory.appendingPathComponent("snapshot.bin")
    }

    /// Old plist location, used only to delete leftover files from the
    /// previous format on first launch after upgrade.
    private static var legacyPlistURL: URL {
        supportDirectory.appendingPathComponent("snapshot.plist")
    }

    private static var supportDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Jubako", isDirectory: true)
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

        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        // Drop any leftover plist from the previous format.
        try? FileManager.default.removeItem(at: legacyPlistURL)
        let started = Date()
        do {
            try BinarySnapshotIO.write(snapshot, to: url)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            let elapsed = Date().timeIntervalSince(started)
            NSLog("Jubako: snapshot saved (%d bytes, %.2fs) at %@", bytes, elapsed, url.path)
        } catch {
            NSLog("Jubako: snapshot save failed: %@", error.localizedDescription)
        }
    }

    public static func load() -> ScanSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let started = Date()
        do {
            let snap = try BinarySnapshotIO.read(from: url)
            let elapsed = Date().timeIntervalSince(started)
            NSLog("Jubako: snapshot loaded (%.2fs)", elapsed)
            return snap
        } catch {
            NSLog("Jubako: snapshot load failed (%@); deleting", error.localizedDescription)
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
