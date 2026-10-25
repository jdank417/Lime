//
//  Actions.swift
//  Lime
//

import Foundation

enum WheelMode {
    /// Shift-drag: change the file's format.
    case convert
    /// Option-drag: edit it without changing format.
    case tools

    var title: String { self == .convert ? "Convert" : "Tools" }
}

/// One slice of the wheel.
struct LimeAction: Identifiable {
    let id: String
    /// Short text on the wedge, e.g. "PNG".
    let label: String
    /// Shown in the wheel's center while hovered, and in the HUD.
    let title: String
    let symbol: String
    let run: ([URL]) async throws -> [URL]

    /// An action that handles each file on its own.
    static func each(_ id: String, _ label: String, _ title: String, _ symbol: String,
                     _ body: @escaping (URL) async throws -> URL) -> LimeAction {
        LimeAction(id: id, label: label, title: title, symbol: symbol) { urls in
            var outputs: [URL] = []
            for url in urls { outputs.append(try await body(url)) }
            return outputs
        }
    }

    /// An action that turns all files into a single result.
    static func all(_ id: String, _ label: String, _ title: String, _ symbol: String,
                    _ body: @escaping ([URL]) async throws -> URL) -> LimeAction {
        LimeAction(id: id, label: label, title: title, symbol: symbol) { [try await body($0)] }
    }
}

enum ActionCatalog {
    static let maxWedges = 10

    static func actions(for urls: [URL], mode: WheelMode) -> [LimeAction] {
        guard !urls.isEmpty else { return [] }
        let kinds = Set(urls.map(FileKind.of))
        guard kinds.count == 1, let kind = kinds.first else {
            return mode == .convert ? [zip, tarGz] : [zip]
        }
        // Don't offer "PNG" for a PNG. Only applies when every file shares the extension.
        let exts = Set(urls.map { normalizedExtension(of: $0) })
        let source = exts.count == 1 ? exts.first! : ""
        let many = urls.count > 1

        let list: [LimeAction]
        switch (kind, mode) {
        case (.image, .convert):
            list = (many ? [combineImages] : []) + ImageConverter.targets.filter { $0.ext != source }.map { target in
                .each("image.\(target.ext)", target.label, "Convert to \(target.label)", "photo") { url in
                    try await offMain { try ImageConverter.convert(url, to: target) }
                }
            }
        case (.image, .tools):
            list = [
                imageEdit(.halfSize, "½ Size", "Resize to half size", "arrow.down.right.and.arrow.up.left"),
                imageEdit(.rotate, "Rotate", "Rotate 90° clockwise", "rotate.right"),
                imageEdit(.flip, "Flip", "Flip horizontally", "arrow.left.and.right.righttriangle.left.righttriangle.right"),
                imageEdit(.grayscale, "Mono", "Make black & white", "circle.lefthalf.filled"),
                imageEdit(.compress, "Shrink", "Compress as JPG", "arrow.down.circle"),
                imageEdit(.stripMetadata, "Clean", "Remove metadata", "eye.slash"),
                zip,
            ]

        case (.video, .convert):
            list = MediaConverter.videoTargets.filter { $0.ext != source || $0.suffix != nil }.map { target in
                .each("video.\(target.label)", target.label, "Convert to \(target.label)", "film") { url in
                    try await MediaConverter.convert(url, to: target)
                }
            } + [
                .each("video.gif", "GIF", "Make an animated GIF", "photo.stack") { try await MediaConverter.gif($0) },
                .each("video.m4a", "M4A", "Extract the audio", "waveform") { try await MediaConverter.extractAudio($0) },
            ]
        case (.video, .tools):
            list = MediaConverter.resizeTargets.map { target in
                .each("video.\(target.label)", target.label, "Resize to \(target.label)", "arrow.down.right.and.arrow.up.left") { url in
                    try await MediaConverter.convert(url, to: target)
                }
            } + [
                .each("video.mute", "Mute", "Remove the audio", "speaker.slash") { try await MediaConverter.removeAudio($0) },
                .each("video.frame", "Frame", "Save the first frame", "camera") { try await MediaConverter.snapshot($0) },
                zip,
            ]

        case (.audio, .convert):
            list = MediaConverter.audioTargets.filter { $0.ext != source || $0.suffix != nil }.map { target in
                .each("audio.\(target.label)", target.label, "Convert to \(target.label)", "waveform") { url in
                    try await offMain { try MediaConverter.convert(url, to: target) }
                }
            }
        case (.audio, .tools):
            let target = MediaConverter.compressAudio
            list = [
                .each("audio.compress", "Shrink", "Compress to a small M4A", "arrow.down.circle") { url in
                    try await offMain { try MediaConverter.convert(url, to: target) }
                },
                zip,
            ]

        case (.pdf, .convert):
            list = (many ? [mergePDFs] : []) + [ImageConverter.png, ImageConverter.jpeg].map { target in
                .each("pdf.\(target.ext)", target.label, "Convert pages to \(target.label)", "photo") { url in
                    try await offMain { try PDFConverter.toImages(url, target: target) }
                }
            } + [
                .each("pdf.txt", "TXT", "Extract the text", "text.alignleft") { url in
                    try await offMain { try PDFConverter.toText(url) }
                },
            ] + DocumentConverter.targets.filter { ["rtf", "docx"].contains($0.ext) }.map { target in
                .each("pdf.\(target.ext)", target.label, "Convert to \(target.label)", "doc.text") { url in
                    let out = Output.url(for: url, ext: target.ext)
                    try DocumentConverter.write(try PDFConverter.attributedText(url), to: out, type: target.type)
                    return out
                }
            }
        case (.pdf, .tools):
            list = [
                .each("pdf.compress", "Shrink", "Compress the PDF", "arrow.down.circle") { url in
                    try await offMain { try PDFConverter.compress(url) }
                },
                .each("pdf.rotate", "Rotate", "Rotate pages 90°", "rotate.right") { url in
                    try await offMain { try PDFConverter.rotate(url) }
                },
                .each("pdf.split", "Split", "Split into single pages", "scissors") { url in
                    try await offMain { try PDFConverter.split(url) }
                },
            ] + (many ? [mergePDFs] : []) + [zip]

        case (.document, .convert):
            list = DocumentConverter.targets.filter { $0.ext != source }.map { target in
                .each("doc.\(target.ext)", target.label, "Convert to \(target.label)", "doc.text") { url in
                    try DocumentConverter.convert(url, to: target)
                }
            }

        case (.archive, .convert):
            list = [
                .each("archive.extract", "Extract", "Extract the contents", "shippingbox.and.arrow.backward") {
                    try await ArchiveTool.extract($0)
                },
            ] + [("zip", "ZIP"), ("tar.gz", "TAR.GZ")].filter { $0.0 != source }.map { ext, label in
                .each("archive.\(ext)", label, "Repack as \(label)", "archivebox") { try await ArchiveTool.repack($0, as: ext) }
            }

        case (.folder, .convert):
            list = [
                zip,
                tarGz,
                .each("folder.dmg", "DMG", "Make a disk image", "externaldrive") { try await ArchiveTool.diskImage($0) },
            ]

        case (_, .convert):
            list = [zip, tarGz]
        case (_, .tools):
            list = [zip]
        }
        return Array(list.prefix(maxWedges))
    }

    // MARK: Shared actions

    private static let zip = LimeAction.all("zip", "ZIP", "Compress as ZIP", "doc.zipper") {
        try await ArchiveTool.zip($0)
    }

    private static let tarGz = LimeAction.all("tar.gz", "TAR.GZ", "Compress as TAR.GZ", "archivebox") {
        try await ArchiveTool.tarGz($0)
    }

    private static let combineImages = LimeAction.all("image.combine", "1 PDF", "Combine into one PDF", "doc.on.doc") { urls in
        try await offMain { try ImageConverter.combineIntoPDF(urls) }
    }

    private static let mergePDFs = LimeAction.all("pdf.merge", "Merge", "Merge into one PDF", "doc.on.doc") { urls in
        try await offMain { try PDFConverter.merge(urls) }
    }

    private static func imageEdit(_ edit: ImageConverter.Edit, _ label: String, _ title: String, _ symbol: String) -> LimeAction {
        .each("image.\(edit)", label, title, symbol) { url in
            try await offMain { try ImageConverter.edit(url, edit) }
        }
    }
}
