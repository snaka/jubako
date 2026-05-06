import Foundation
import SwiftUI

/// Coarse classification used for color coding and (eventually) the
/// "Categories" view. Rules are applied in order; first match wins.
public enum FileCategory: String, CaseIterable, Sendable {
    case system
    case docker
    case simulator
    case devCache
    case browserCache
    case appCache
    case downloads
    case media
    case archive
    case userDocument
    case userFolder

    /// Basenames that, when they appear *anywhere* in a path, mark everything
    /// under them as a development cache.
    private static let devCacheBasenames: Set<String> = [
        "DerivedData",
        "node_modules",
        "target",
        "Pods",
        ".gradle",
        ".cargo",
        ".next",
        ".nuxt",
        "dist",
        "build",
        ".venv",
        "__pycache__",
        ".bundle",
        ".npm",
        ".yarn",
        ".pnpm",
        ".cocoapods",
        ".swiftpm",
        ".m2",
        ".nuget",
    ]

    private static let mediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "gif", "webp", "tiff", "bmp",
        "mov", "mp4", "mkv", "avi", "webm", "m4v",
        "mp3", "flac", "wav", "m4a", "aac", "aiff", "ogg",
    ]

    private static let archiveExtensions: Set<String> = [
        "zip", "dmg", "tar", "gz", "tgz", "bz2", "tbz", "xz",
        "7z", "rar", "iso", "pkg",
    ]

    public static func classify(path: String, isDirectory: Bool) -> FileCategory {
        // /System and /Library at the root are macOS-managed.
        if path.hasPrefix("/System/") || path.hasPrefix("/Library/")
            || path == "/System" || path == "/Library" {
            return .system
        }

        // Specific paths under user Library.
        if path.contains("/Library/Containers/com.docker.docker/") {
            return .docker
        }
        if path.contains("/Library/Developer/CoreSimulator/") {
            return .simulator
        }
        if let cachesRange = path.range(of: "/Library/Caches/") {
            let suffix = path[cachesRange.upperBound...]
            if suffix.hasPrefix("Google/Chrome")
                || suffix.hasPrefix("com.apple.Safari")
                || suffix.hasPrefix("Firefox")
                || suffix.hasPrefix("com.google.Chrome") {
                return .browserCache
            }
            return .appCache
        }
        if path.contains("/Downloads/") || (path as NSString).lastPathComponent == "Downloads" {
            return .downloads
        }

        // Dev cache: any path component matching a known cache basename.
        let basename = (path as NSString).lastPathComponent
        if devCacheBasenames.contains(basename) {
            return .devCache
        }
        for component in path.split(separator: "/") where devCacheBasenames.contains(String(component)) {
            return .devCache
        }

        if !isDirectory {
            let ext = (path as NSString).pathExtension.lowercased()
            if mediaExtensions.contains(ext) { return .media }
            if archiveExtensions.contains(ext) { return .archive }
            return .userDocument
        }

        return .userFolder
    }
}

public extension FileCategory {
    var tintColor: Color {
        switch self {
        case .system:        return .red
        case .docker:        return .cyan
        case .simulator:     return .indigo
        case .devCache:      return .orange
        case .browserCache:  return .pink
        case .appCache:      return .teal
        case .downloads:     return .yellow
        case .media:         return .purple
        case .archive:       return .brown
        case .userDocument:  return .gray
        case .userFolder:    return .blue
        }
    }

    var iconName: String {
        switch self {
        case .system:        return "lock.fill"
        case .docker:        return "shippingbox.fill"
        case .simulator:     return "iphone"
        case .devCache:      return "hammer.fill"
        case .browserCache:  return "globe"
        case .appCache:      return "internaldrive.fill"
        case .downloads:     return "arrow.down.circle.fill"
        case .media:         return "photo.fill"
        case .archive:       return "archivebox.fill"
        case .userDocument:  return "doc.fill"
        case .userFolder:    return "folder.fill"
        }
    }

    var label: String {
        switch self {
        case .system:        return "System"
        case .docker:        return "Docker"
        case .simulator:     return "Simulator"
        case .devCache:      return "Dev cache"
        case .browserCache:  return "Browser cache"
        case .appCache:      return "App cache"
        case .downloads:     return "Downloads"
        case .media:         return "Media"
        case .archive:       return "Archive"
        case .userDocument:  return "Document"
        case .userFolder:    return "Folder"
        }
    }
}

public extension ScanEntry {
    var category: FileCategory {
        FileCategory.classify(path: path, isDirectory: isDirectory)
    }
}
