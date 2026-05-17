import Foundation
import AppKit

/// Information about a macOS application owning a given filesystem path.
public struct AppInfo: Equatable, Sendable {
    public let bundleID: String?
    public let displayName: String
    public let appURL: URL?
}

/// Resolves filesystem paths to the macOS application that owns them, using
/// Apple's standard `~/Library` conventions.
///
/// Lookups go through a single shared cache so repeated calls for the same
/// bundle-id (or app name) hit memory after the first resolution. The cache
/// is keyed on the *identifier*, not the path, because many distinct paths
/// (e.g. Containers / Caches / Preferences) point at the same app.
@MainActor
public final class AppResolver {
    public static let shared = AppResolver()

    private let homePrefix: String
    private var cache: [String: AppInfo?] = [:]

    private init() {
        var home = NSHomeDirectory()
        if !home.hasSuffix("/") { home += "/" }
        self.homePrefix = home
    }

    /// Looks up the app that owns `path`. Returns `nil` if the path doesn't
    /// match a known convention, or if LaunchServices can't resolve the
    /// identifier to an installed app.
    public func appInfo(for path: String) -> AppInfo? {
        guard let identifier = identifier(for: path) else { return nil }
        if let cached = cache[identifier.key] {
            return cached
        }
        let resolved = resolve(identifier)
        cache[identifier.key] = resolved
        return resolved
    }

    // MARK: - Identifier extraction

    enum Identifier {
        case bundleID(String)
        case appName(String)

        var key: String {
            switch self {
            case .bundleID(let s): return "id:" + s
            case .appName(let s):  return "name:" + s
            }
        }
    }

    func identifier(for path: String) -> Identifier? {
        // /Applications/<Name>.app — the app bundle itself.
        if path.hasPrefix("/Applications/") || path.hasPrefix(homePrefix + "Applications/") {
            let basename = (path as NSString).lastPathComponent
            if basename.hasSuffix(".app") {
                let name = String(basename.dropLast(4))
                return .appName(name)
            }
        }

        // Below this point we only handle paths under the user's `~/Library/`.
        let libraryPrefix = homePrefix + "Library/"
        guard path.hasPrefix(libraryPrefix) else { return nil }
        let suffix = String(path.dropFirst(libraryPrefix.count))

        // The first two components determine the pattern.
        let parts = suffix.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        let bucket = String(parts[0])
        let leaf = String(parts[1])
        if leaf.isEmpty { return nil }

        switch bucket {
        case "Containers", "Caches", "HTTPStorages", "WebKit", "Group Containers":
            return .bundleID(leaf)
        case "Saved Application State":
            // <bundle-id>.savedState
            if leaf.hasSuffix(".savedState") {
                return .bundleID(String(leaf.dropLast(".savedState".count)))
            }
            return nil
        case "Preferences":
            // <bundle-id>.plist
            if leaf.hasSuffix(".plist") {
                return .bundleID(String(leaf.dropLast(".plist".count)))
            }
            return nil
        case "Application Support", "Logs":
            // Usually `<App Name>/...`, sometimes `<bundle-id>/...`. Heuristic:
            // a string with two or more dots and no spaces looks like a
            // reverse-DNS bundle id; otherwise treat it as an app name.
            if looksLikeBundleID(leaf) {
                return .bundleID(leaf)
            }
            return .appName(leaf)
        default:
            return nil
        }
    }

    private func looksLikeBundleID(_ s: String) -> Bool {
        // Reverse-DNS heuristic: at least two dots, no spaces, mostly
        // alphanumerics or dashes between dots. "com.apple.Safari" matches;
        // "Adobe Photoshop 2024" does not.
        guard s.contains("."), !s.contains(" ") else { return false }
        let dots = s.reduce(into: 0) { acc, c in if c == "." { acc += 1 } }
        return dots >= 2
    }

    // MARK: - LaunchServices resolution

    private func resolve(_ identifier: Identifier) -> AppInfo? {
        switch identifier {
        case .bundleID(let id):
            return resolveBundleID(id)
        case .appName(let name):
            return resolveAppName(name)
        }
    }

    private func resolveBundleID(_ bundleID: String) -> AppInfo? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            // Couldn't find the app on disk. We still know the bundle ID,
            // which is usually enough to be useful in the UI — return a
            // sentinel AppInfo so the caller can show "com.apple.Safari".
            return AppInfo(bundleID: bundleID, displayName: bundleID, appURL: nil)
        }
        let name = readDisplayName(at: url) ?? url.deletingPathExtension().lastPathComponent
        return AppInfo(bundleID: bundleID, displayName: name, appURL: url)
    }

    private func resolveAppName(_ name: String) -> AppInfo? {
        // Probe well-known locations first; faster than NSMetadataQuery and
        // covers the common case.
        let candidates: [URL] = [
            URL(fileURLWithPath: "/Applications/\(name).app"),
            URL(fileURLWithPath: homePrefix + "Applications/\(name).app"),
            URL(fileURLWithPath: "/System/Applications/\(name).app"),
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            let bid = Bundle(url: url)?.bundleIdentifier
            let display = readDisplayName(at: url) ?? name
            return AppInfo(bundleID: bid, displayName: display, appURL: url)
        }
        // Not found on disk. Return the bare folder name as a fallback so the
        // UI can still print something useful (e.g. "Cursor").
        return AppInfo(bundleID: nil, displayName: name, appURL: nil)
    }

    private func readDisplayName(at url: URL) -> String? {
        guard let info = Bundle(url: url)?.infoDictionary else { return nil }
        if let n = info["CFBundleDisplayName"] as? String, !n.isEmpty { return n }
        if let n = info["CFBundleName"] as? String, !n.isEmpty { return n }
        return nil
    }

    /// Fetches an `NSImage` for the resolved app. Kept separate from the
    /// resolution call because icons can be sizeable in memory and aren't
    /// always needed (e.g. unit-test paths).
    public func icon(for info: AppInfo) -> NSImage? {
        guard let url = info.appURL else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
