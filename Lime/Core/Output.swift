//
//  Output.swift
//  Lime
//

import Foundation

/// Picks where converted files go: next to the original, never overwriting anything.
nonisolated enum Output {
    /// "photo.heic" + "png" → "photo.png" (or "photo 2.png" if taken), in the folder from Settings.
    static func url(for source: URL, ext: String, suffix: String? = nil) -> URL {
        url(in: directory(for: source), base: baseName(of: source), ext: ext, suffix: suffix)
    }

    /// Where results of `source` go: beside it, in Downloads, or in the chosen folder.
    static func directory(for source: URL) -> URL {
        let beside = source.deletingLastPathComponent()
        switch Prefs.saveLocation {
        case .beside:
            return beside
        case .downloads:
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? beside
        case .folder:
            guard let folder = Prefs.customFolder, FileManager.default.fileExists(atPath: folder.path) else { return beside }
            return folder
        }
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
/// The box lets framework objects (CIImage, NSImage…) that aren't marked Sendable come back out.
nonisolated func offMain<T>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await Task.detached(priority: .userInitiated) { UncheckedBox(value: try work()) }.value.value
}

nonisolated struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
}

/// Lets long jobs move the island's progress bar. Each file of a batch gets its own slice of the bar.
nonisolated enum JobProgress {
    @TaskLocal static var span: ClosedRange<Double> = 0...1

    static func report(_ fraction: Double) {
        let span = span
        let value = span.lowerBound + (span.upperBound - span.lowerBound) * min(max(fraction, 0), 1)
        Task { @MainActor in Island.shared.setProgress(value) }
    }
}
