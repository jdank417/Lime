//
//  ArchiveTool.swift
//  Lime
//

import Foundation

/// Archives through the command-line tools every Mac ships with.
nonisolated enum ArchiveTool {
    /// "photo.jpg" → "photo.jpg.zip", like Finder's Compress. Several files → "Archive.zip".
    static func zip(_ urls: [URL]) async throws -> URL {
        let dir = urls[0].deletingLastPathComponent()
        if urls.count == 1 {
            let out = Output.url(in: dir, base: urls[0].lastPathComponent, ext: "zip")
            try await run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", urls[0].path, out.path])
            return out
        }
        let out = Output.url(in: dir, base: "Archive", ext: "zip")
        try await run("/usr/bin/zip", ["-r", "-y", "-q", out.path] + urls.map(\.lastPathComponent), in: dir)
        return out
    }

    static func tarGz(_ urls: [URL]) async throws -> URL {
        let dir = urls[0].deletingLastPathComponent()
        let base = urls.count == 1 ? Output.baseName(of: urls[0]) : "Archive"
        let out = Output.url(in: dir, base: base, ext: "tar.gz")
        try await run("/usr/bin/tar", ["-czf", out.path, "-C", dir.path] + urls.map(\.lastPathComponent))
        return out
    }

    static func diskImage(_ folder: URL) async throws -> URL {
        let out = Output.url(in: folder.deletingLastPathComponent(), base: folder.lastPathComponent, ext: "dmg")
        try await run("/usr/bin/hdiutil", ["create", "-quiet", "-volname", folder.lastPathComponent,
                                           "-srcfolder", folder.path, "-format", "UDZO", out.path])
        return out
    }

    /// Unpacks next to the archive. If it holds a single item, that item comes out directly.
    static func extract(_ url: URL) async throws -> URL {
        let parent = url.deletingLastPathComponent()
        // Unpack into a hidden folder beside the archive (same volume, so the final move is instant)
        // so it doesn't claim the name the result should get.
        let scratch = parent.appendingPathComponent(".lime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try await unpack(url, into: scratch)

        let items = try visibleContents(of: scratch)
        let item: URL, destination: URL
        if items.count == 1 {
            item = items[0]
            let ext = FileKind.of(item) == .folder ? "" : item.pathExtension
            destination = Output.url(in: parent, base: ext.isEmpty ? item.lastPathComponent : item.deletingPathExtension().lastPathComponent, ext: ext)
        } else {
            try? FileManager.default.removeItem(at: scratch.appendingPathComponent("__MACOSX"))
            item = scratch
            destination = Output.url(in: parent, base: Output.baseName(of: url), ext: "")
        }
        try FileManager.default.moveItem(at: item, to: destination)
        return destination
    }

    /// Repackages one archive format as another by unpacking to a scratch folder.
    static func repack(_ url: URL, as format: String) async throws -> URL {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try await unpack(url, into: scratch)

        let names = try visibleContents(of: scratch).map(\.lastPathComponent)
        let out = Output.url(in: url.deletingLastPathComponent(), base: Output.baseName(of: url), ext: format)
        if format == "zip" {
            try await run("/usr/bin/zip", ["-r", "-y", "-q", out.path] + names, in: scratch)
        } else {
            try await run("/usr/bin/tar", ["-czf", out.path, "-C", scratch.path] + names)
        }
        return out
    }

    private static func unpack(_ url: URL, into folder: URL) async throws {
        if normalizedExtension(of: url) == "zip" {
            try await run("/usr/bin/ditto", ["-x", "-k", url.path, folder.path])
        } else {
            // bsdtar reads tar, gz, bz2, xz, 7z, iso, xar and more.
            try await run("/usr/bin/tar", ["-xf", url.path, "-C", folder.path])
        }
    }

    private static func visibleContents(of folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "__MACOSX" }
    }

    private static func run(_ tool: String, _ arguments: [String], in dir: URL? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            if let dir { process.currentDirectoryURL = dir }
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = FileHandle.nullDevice
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: LimeError.failed(message.isEmpty ? "\(tool) failed" : message))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
