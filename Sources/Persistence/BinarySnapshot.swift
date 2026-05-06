import Foundation

/// Flat little-endian binary serialization for ScanSnapshot. Built to be much
/// faster than PropertyListEncoder/JSONEncoder for the large-snapshot case
/// (1M+ entries) — those encoders box every value individually, which is
/// where most of their time goes.
///
/// Format (all little-endian):
///   magic:        4 bytes ('JBKO')
///   version:      4 bytes UInt32
///   scannedAt:    8 bytes Float64 (timeIntervalSince1970)
///   totalFiles:   8 bytes Int64
///   totalBytes:   8 bytes Int64
///   elapsed:      8 bytes Float64
///   errorCount:   4 bytes UInt32
///   rootPath:     u32 length + utf-8 bytes
///   lastError:    u32 length + utf-8 bytes
///   deferredCount: u32 + (u32 length + utf-8 bytes)*
///   parentCount:  u32
///   for each parent:
///     parent:     u32 length + utf-8 bytes
///     childCount: u32
///     for each child:
///       path:       u32 length + utf-8 bytes
///       size:       i64
///       isDirectory: u8
///       modifiedAt: f64
///       accessedAt: f64
enum BinarySnapshotIO {
    // ASCII 'J' 'B' 'K' 'O' little-endian.
    private static let magic: UInt32 = 0x4F4B424A
    private static let formatVersion: UInt32 = 1

    enum Error: Swift.Error {
        case badMagic
        case unsupportedVersion(UInt32)
        case truncated
        case invalidString
    }

    // MARK: Write

    static func write(_ snapshot: ScanSnapshot, to url: URL) throws {
        var data = Data()
        data.reserveCapacity(64 * 1024 * 1024)

        appendUInt32(magic, to: &data)
        appendUInt32(formatVersion, to: &data)
        appendDouble(snapshot.scannedAt.timeIntervalSince1970, to: &data)
        appendInt64(Int64(snapshot.totalFiles), to: &data)
        appendInt64(snapshot.totalBytes, to: &data)
        appendDouble(snapshot.elapsed, to: &data)
        appendUInt32(UInt32(truncatingIfNeeded: snapshot.errorCount), to: &data)
        appendString(snapshot.rootPath, to: &data)
        appendString(snapshot.lastError, to: &data)

        appendUInt32(UInt32(snapshot.deferredPaths.count), to: &data)
        for p in snapshot.deferredPaths {
            appendString(p, to: &data)
        }

        appendUInt32(UInt32(snapshot.entriesByParent.count), to: &data)
        for (parent, children) in snapshot.entriesByParent {
            appendString(parent, to: &data)
            appendUInt32(UInt32(children.count), to: &data)
            for c in children {
                appendString(c.path, to: &data)
                appendInt64(c.size, to: &data)
                data.append(c.isDirectory ? 1 : 0)
                appendDouble(c.modifiedAt.timeIntervalSince1970, to: &data)
                appendDouble(c.accessedAt.timeIntervalSince1970, to: &data)
            }
        }

        try data.write(to: url, options: .atomic)
    }

    // MARK: Read

    static func read(from url: URL) throws -> ScanSnapshot {
        let data = try Data(contentsOf: url)
        var c = 0

        let m = try readUInt32(data, &c)
        guard m == magic else { throw Error.badMagic }
        let v = try readUInt32(data, &c)
        guard v == formatVersion else { throw Error.unsupportedVersion(v) }

        let scannedAt = try readDouble(data, &c)
        let totalFiles = try readInt64(data, &c)
        let totalBytes = try readInt64(data, &c)
        let elapsed = try readDouble(data, &c)
        let errorCount = Int(try readUInt32(data, &c))
        let rootPath = try readString(data, &c)
        let lastError = try readString(data, &c)

        let deferredCount = Int(try readUInt32(data, &c))
        var deferredPaths: [String] = []
        deferredPaths.reserveCapacity(deferredCount)
        for _ in 0..<deferredCount {
            deferredPaths.append(try readString(data, &c))
        }

        let parentCount = Int(try readUInt32(data, &c))
        var byParent: [String: [ScanEntry]] = [:]
        byParent.reserveCapacity(parentCount)
        for _ in 0..<parentCount {
            let parent = try readString(data, &c)
            let childCount = Int(try readUInt32(data, &c))
            var children: [ScanEntry] = []
            children.reserveCapacity(childCount)
            for _ in 0..<childCount {
                let path = try readString(data, &c)
                let size = try readInt64(data, &c)
                guard c < data.count else { throw Error.truncated }
                let isDir = (data[data.startIndex + c] != 0)
                c += 1
                let mt = try readDouble(data, &c)
                let at = try readDouble(data, &c)
                children.append(ScanEntry(
                    path: path,
                    size: size,
                    isDirectory: isDir,
                    modifiedAt: Date(timeIntervalSince1970: mt),
                    accessedAt: Date(timeIntervalSince1970: at)
                ))
            }
            byParent[parent] = children
        }

        return ScanSnapshot(
            scannedAt: Date(timeIntervalSince1970: scannedAt),
            rootPath: rootPath,
            totalFiles: Int(totalFiles),
            totalBytes: totalBytes,
            elapsed: elapsed,
            errorCount: errorCount,
            lastError: lastError,
            deferredPaths: deferredPaths,
            entriesByParent: byParent
        )
    }

    // MARK: Primitive writers

    @inline(__always)
    private static func appendUInt32(_ v: UInt32, to data: inout Data) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    @inline(__always)
    private static func appendInt64(_ v: Int64, to data: inout Data) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    @inline(__always)
    private static func appendDouble(_ v: Double, to data: inout Data) {
        var bits = v.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }

    @inline(__always)
    private static func appendString(_ s: String, to data: inout Data) {
        let utf8 = s.utf8
        appendUInt32(UInt32(utf8.count), to: &data)
        data.append(contentsOf: utf8)
    }

    // MARK: Primitive readers

    @inline(__always)
    private static func readUInt32(_ data: Data, _ cursor: inout Int) throws -> UInt32 {
        guard cursor + 4 <= data.count else { throw Error.truncated }
        var v: UInt32 = 0
        withUnsafeMutableBytes(of: &v) { dst in
            data.copyBytes(
                to: dst.bindMemory(to: UInt8.self),
                from: (data.startIndex + cursor)..<(data.startIndex + cursor + 4)
            )
        }
        cursor += 4
        return UInt32(littleEndian: v)
    }

    @inline(__always)
    private static func readInt64(_ data: Data, _ cursor: inout Int) throws -> Int64 {
        guard cursor + 8 <= data.count else { throw Error.truncated }
        var v: Int64 = 0
        withUnsafeMutableBytes(of: &v) { dst in
            data.copyBytes(
                to: dst.bindMemory(to: UInt8.self),
                from: (data.startIndex + cursor)..<(data.startIndex + cursor + 8)
            )
        }
        cursor += 8
        return Int64(littleEndian: v)
    }

    @inline(__always)
    private static func readDouble(_ data: Data, _ cursor: inout Int) throws -> Double {
        guard cursor + 8 <= data.count else { throw Error.truncated }
        var bits: UInt64 = 0
        withUnsafeMutableBytes(of: &bits) { dst in
            data.copyBytes(
                to: dst.bindMemory(to: UInt8.self),
                from: (data.startIndex + cursor)..<(data.startIndex + cursor + 8)
            )
        }
        cursor += 8
        return Double(bitPattern: UInt64(littleEndian: bits))
    }

    @inline(__always)
    private static func readString(_ data: Data, _ cursor: inout Int) throws -> String {
        let len = Int(try readUInt32(data, &cursor))
        guard cursor + len <= data.count else { throw Error.truncated }
        let start = data.startIndex + cursor
        let slice = data[start..<(start + len)]
        cursor += len
        return slice.withUnsafeBytes { rawBuf -> String in
            let p = rawBuf.bindMemory(to: UInt8.self)
            let buf = UnsafeBufferPointer(start: p.baseAddress, count: len)
            return String(decoding: buf, as: UTF8.self)
        }
    }
}
