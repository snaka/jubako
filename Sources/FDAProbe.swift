import Foundation

/// Detects whether the app has Full Disk Access by trying to read TCC-protected
/// paths. macOS provides no direct API for this; the standard practice is to
/// list a known protected directory and check whether the call succeeds.
enum FDAProbe {
    /// Paths that are TCC-protected on a default macOS install. We try each in
    /// order and return true as soon as one read succeeds.
    private static let candidates: [String] = [
        "Library/Safari",
        "Library/Mail",
        "Library/Containers/com.apple.Safari",
    ]

    static func hasAccess() -> Bool {
        let home = NSHomeDirectory() as NSString
        for sub in candidates {
            let path = home.appendingPathComponent(sub)
            if (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil {
                return true
            }
        }
        return false
    }
}
