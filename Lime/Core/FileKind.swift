//
//  FileKind.swift
//  Lime
//

import Foundation
import UniformTypeIdentifiers

/// The broad family a dropped file belongs to. Decides which actions the wheel offers.
nonisolated enum FileKind: Sendable {
    case image, video, audio, pdf, document, subtitle, archive, folder, other

    static func of(_ url: URL) -> FileKind {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .contentTypeKey])
        if values?.isDirectory == true && values?.isPackage != true { return .folder }
        if ["srt", "vtt"].contains(url.pathExtension.lowercased()) { return .subtitle }
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
        return of(type)
    }

    static func of(_ type: UTType) -> FileKind {
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if [.archive, .zip, .gzip, .bz2].contains(where: type.conforms) { return .archive }
        if documentTypes.contains(where: type.conforms) { return .document }
        return .other
    }

    private static let documentTypes: [UTType] = [.text, .rtf, .rtfd, .html, .webArchive] + [
        "org.openxmlformats.wordprocessingml.document",
        "com.microsoft.word.doc",
        "org.oasis-open.opendocument.text",
        "net.daringfireball.markdown",
    ].compactMap { UTType($0) }
}

/// Lowercased extension with common spellings folded together, so "photo.jpeg" isn't offered "JPG".
nonisolated func normalizedExtension(_ ext: String) -> String {
    let ext = ext.lowercased()
    let aliases = ["jpeg": "jpg", "tif": "tiff", "aif": "aiff", "htm": "html", "markdown": "md", "tgz": "tar.gz"]
    return aliases[ext] ?? ext
}

nonisolated func normalizedExtension(of url: URL) -> String {
    let name = url.lastPathComponent.lowercased()
    for compound in ["tar.gz", "tar.bz2", "tar.xz"] where name.hasSuffix("." + compound) { return compound }
    return normalizedExtension(url.pathExtension)
}
