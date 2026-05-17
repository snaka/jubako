import Foundation

/// Filesystem capacity / availability for the volume containing a given path.
///
/// Values come from `URL.resourceValues(forKeys:)` and are reported in bytes
/// of "logical" capacity — the same numbers Finder shows in Get Info. APFS
/// snapshots and other purgeable storage are accounted for as available space.
public struct VolumeUsage: Sendable, Equatable {
    public let totalBytes: Int64
    public let availableBytes: Int64
    public let volumeName: String
    public let volumePath: String

    public var usedBytes: Int64 {
        max(0, totalBytes - availableBytes)
    }

    /// Read the volume containing `path`. Returns nil if the path can't be
    /// resolved or the OS doesn't expose capacity keys (e.g. a stale mount).
    public static func forPath(_ path: String) -> VolumeUsage? {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeNameKey,
            .volumeURLKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        guard let total = values.volumeTotalCapacity else { return nil }
        // Prefer the "important usage" number because it matches Finder's free
        // figure (it counts purgeable space). Fall back to the strict number
        // if the OS doesn't supply it.
        let available: Int64
        if let importantInt64 = values.volumeAvailableCapacityForImportantUsage {
            available = importantInt64
        } else if let plain = values.volumeAvailableCapacity {
            available = Int64(plain)
        } else {
            return nil
        }
        let volumeURL = values.volume ?? url
        let name = values.volumeName ?? volumeURL.lastPathComponent
        return VolumeUsage(
            totalBytes: Int64(total),
            availableBytes: available,
            volumeName: name,
            volumePath: volumeURL.path
        )
    }
}
