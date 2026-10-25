//
//  Output.swift
//  Lime
//

import Foundation

/// Picks where converted files go: next to the original, never overwriting anything.
nonisolated enum Output {
    /// "photo.heic" + "png" → "photo.png" (or "photo 2.png" if taken).
    static func url(for source: URL, ext: String, suffix: String? = nil) -> URL {
        url(in: source.deletingLastPathComponent(), base: baseName(of: source), ext: ext, suffix: suffix)
    }

    /// An empty `ext` produces a folder URL.
    static func url(in dir: URL, base: String, ext: String, suffix: String? = nil) -> URL {
        let stem = suffix.map { "\(base) (\($0))" } ?? base
        func make(_ name: String) -> URL {
            ext.isEmpty
                ? dir.appendingPathComponent(name, isDirectory: true)
                : dir.appendingPathComponent(name + "." + ext)
        }
        var candidate = make(stem)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = make("\(stem) \(n)")
            n += 1
        }
        return candidate
    }

    /// File name without its extension; folders keep their whole name.
    static func baseName(of url: URL) -> String {
        let name = url.lastPathComponent
        if FileKind.of(url) == .folder { return name }
        for compound in [".tar.gz", ".tar.bz2", ".tar.xz"] where name.lowercased().hasSuffix(compound) {
            return String(name.dropLast(compound.count))
        }
        return url.deletingPathExtension().lastPathComponent
    }
}

nonisolated enum LimeError: LocalizedError {
    case unreadable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): "Couldn't read \(name)"
        case .failed(let message): message
        }
    }
}

/// Runs blocking conversion work away from the main thread.
nonisolated func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await Task.detached(priority: .userInitiated, operation: work).value
}
