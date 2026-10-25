//
//  Actions.swift
//  Lime
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

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
    /// Opens a tool window instead of running straight away.
    var interactive = false
    let run: ([URL]) async throws -> [URL]

    /// An action that handles each file on its own.
    static func each(_ id: String, _ label: String, _ title: String, _ symbol: String,
                     _ body: @escaping (URL) async throws -> URL) -> LimeAction {
        LimeAction(id: id, label: label, title: title, symbol: symbol) { urls in
            var outputs: [URL] = []
            for (index, url) in urls.enumerated() {
                let share = 1 / Double(urls.count)
                let span = Double(index) * share...Double(index + 1) * share
                outputs.append(try await JobProgress.$span.withValue(span) { try await body(url) })
                if urls.count > 1 { JobProgress.report(span.upperBound) }
            }
            return outputs
        }
    }

    /// An action that opens a tool window and waits for it.
    static func tool(_ id: String, _ label: String, _ title: String, _ symbol: String,
                     _ open: @escaping ([URL]) async throws -> [URL]) -> LimeAction {
        LimeAction(id: id, label: label, title: title, symbol: symbol, interactive: true, run: open)
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
            let raster = ImageConverter.targets.filter { $0.type != .pdf && $0.ext != source }.map { convertImage($0) }
            let pdf = ImageConverter.targets.filter { $0.type == .pdf }.map { convertImage($0) }
            list = (many ? [combineImages, collage] : []) + raster + (source == "svg" ? [] : [svg]) + pdf + [imageDocx]
        case (.image, .tools):
            list = many
                ? [compressImages, adjustPhotos, rotateImages, stripMetadata, zip]
                : [compressImages, metadata, adjustPhotos,
                   tool("image.annotate", "Annotate", "Annotate", "pencil.tip.crop.circle", 720, 660) { AnnotateEditor(url: $0[0], session: $1) },
                   tool("image.background", "Add BG", "Add a background", "photo.on.rectangle", 640, 740) { BackgroundEditor(url: $0[0], session: $1) },
                   tool("image.crop", "Crop", "Crop", "crop", 640, 620) { CropEditor(url: $0[0], session: $1) },
                   tool("image.redact", "Redact", "Redact", "eye.slash", 640, 650) { RedactEditor(url: $0[0], session: $1) },
                   rotateImages,
                   tool("image.qr", "QR Code", "Read QR codes", "qrcode.viewfinder", 480, 360) { QRViewer(url: $0[0], session: $1) }]

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
            let compress = tool("video.compress", "Compress", "Compress", "arrow.down.right.and.arrow.up.left", 560, 340) {
                VideoCompressEditor(urls: $0, session: $1)
            }
            let mute = LimeAction.each("video.mute", "Mute", "Remove the audio", "speaker.slash") { try await MediaConverter.removeAudio($0) }
            list = many
                ? [compress, .all("video.join", "Join", "Join into one video", "film.stack") { try await VideoTools.join($0) }, mute, zip]
                : [compress,
                   tool("video.trim", "Trim", "Trim", "timeline.selection", 660, 600) { VideoTrimEditor(url: $0[0], mode: .trim, session: $1) },
                   tool("video.crop", "Crop", "Crop", "crop", 640, 600) { VideoCropEditor(url: $0[0], session: $1) },
                   tool("video.speed", "Speed", "Change speed", "gauge.with.dots.needle.67percent", 540, 330) { SpeedEditor(url: $0[0], session: $1) },
                   tool("video.split", "Split", "Split in two", "scissors", 660, 560) { VideoTrimEditor(url: $0[0], mode: .split, session: $1) },
                   mute,
                   .each("video.frame", "Snapshot", "Save a snapshot", "camera") { try await MediaConverter.snapshot($0) },
                   metadata]

        case (.audio, .convert):
            list = MediaConverter.audioTargets.filter { $0.ext != source || $0.suffix != nil }.map { target in
                .each("audio.\(target.label)", target.label, "Convert to \(target.label)", "waveform") { url in
                    try await offMain { try MediaConverter.convert(url, to: target) }
                }
            }
        case (.audio, .tools):
            let target = MediaConverter.compressAudio
            let compress = LimeAction.each("audio.compress", "Compress", "Compress to a small M4A", "arrow.down.right.and.arrow.up.left") { url in
                try await offMain { try MediaConverter.convert(url, to: target) }
            }
            let normalize = LimeAction.each("audio.normalize", "Normalize", "Normalize the volume", "speaker.wave.3") { url in
                try await offMain { try AudioTools.normalize(url) }
            }
            list = many
                ? [compress, normalize, zip]
                : [compress,
                   tool("audio.trim", "Trim", "Trim", "timeline.selection", 660, 440) { AudioTrimEditor(url: $0[0], session: $1) },
                   normalize,
                   tool("audio.channels", "Channels", "Change channels", "hifispeaker.2", 540, 360) { ChannelsEditor(url: $0[0], session: $1) },
                   metadata]

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
            let compress = LimeAction.each("pdf.compress", "Compress", "Compress the PDF", "arrow.down.right.and.arrow.up.left") { url in
                try await offMain { try PDFConverter.compress(url) }
            }
            let rotate = LimeAction.each("pdf.rotate", "Rotate", "Rotate pages 90°", "rotate.right") { url in
                try await offMain { try PDFConverter.rotate(url) }
            }
            list = many
                ? [mergePDFs, compress, rotate, zip]
                : [compress,
                   tool("pdf.organize", "Organize", "Organize pages", "square.grid.2x2", 700, 640) { PDFOrganizer(url: $0[0], session: $1) },
                   .each("pdf.split", "Split", "Split into single pages", "scissors") { url in
                       try await offMain { try PDFConverter.split(url) }
                   },
                   rotate, metadata, zip]

        case (.document, .convert):
            list = DocumentConverter.targets.filter { $0.ext != source }.map { target in
                .each("doc.\(target.ext)", target.label, "Convert to \(target.label)", "doc.text") { url in
                    try DocumentConverter.convert(url, to: target)
                }
            }

        case (.subtitle, .convert):
            list = SubtitleConverter.targets.filter { $0.1 != source }.map { label, ext in
                .each("subtitle.\(ext)", label, "Convert to \(label)", "captions.bubble") { url in
                    try await offMain { try SubtitleConverter.convert(url, to: ext) }
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

    /// An action whose window is `content`, sized `width` × `height`.
    private static func tool<V: View>(_ id: String, _ label: String, _ title: String, _ symbol: String,
                                      _ width: CGFloat, _ height: CGFloat,
                                      @ViewBuilder _ content: @escaping ([URL], EditorSession) -> V) -> LimeAction {
        .tool(id, label, title, symbol) { urls in
            try await Editor.present(width: width, height: height) { content(urls, $0) }
        }
    }

    // MARK: Shared actions

    private static let zip = LimeAction.all("zip", "ZIP", "Compress as ZIP", "doc.zipper") {
        try await ArchiveTool.zip($0)
    }

    private static let tarGz = LimeAction.all("tar.gz", "TAR.GZ", "Compress as TAR.GZ", "archivebox") {
        try await ArchiveTool.tarGz($0)
    }

    private static let metadata = tool("metadata", "Metadata", "Metadata", "tag", 640, 660) {
        MetadataEditor(url: $0[0], session: $1)
    }

    private static let stripMetadata = LimeAction.each("metadata.strip", "Clean", "Remove metadata", "eye.slash") {
        try await MetadataTool.strip($0)
    }

    private static let compressImages = tool("image.compress", "Compress", "Compress", "arrow.down.right.and.arrow.up.left", 540, 470) {
        CompressImageEditor(urls: $0, session: $1)
    }

    private static let adjustPhotos = tool("image.edit", "Edit", "Edit photo", "slider.horizontal.3", 620, 760) {
        AdjustEditor(urls: $0, session: $1)
    }

    private static let rotateImages = LimeAction.each("image.rotate", "Rotate", "Rotate 90° clockwise", "rotate.right") { url in
        try await offMain { try ImageTools.rotate(url) }
    }

    private static let svg = LimeAction.each("image.svg", "SVG", "Convert to SVG", "scribble") { url in
        try await offMain { try ImageTools.svg(url) }
    }

    private static let imageDocx = LimeAction.each("image.docx", "DOCX", "Put in a Word document", "doc.richtext") { url in
        try await WordImage.document(for: url)
    }

    private static let combineImages = LimeAction.all("image.combine", "1 PDF", "Combine into one PDF", "doc.on.doc") { urls in
        try await offMain { try ImageConverter.combineIntoPDF(urls) }
    }

    private static let collage = LimeAction.all("image.collage", "Collage", "Make a collage", "square.grid.2x2.fill") { urls in
        try await offMain { try ImageTools.collage(urls) }
    }

    private static let mergePDFs = LimeAction.all("pdf.merge", "Merge", "Merge into one PDF", "doc.on.doc") { urls in
        try await offMain { try PDFConverter.merge(urls) }
    }

    private static func convertImage(_ target: ImageConverter.Target) -> LimeAction {
        .each("image.\(target.ext)", target.label, "Convert to \(target.label)", "photo") { url in
            try await offMain { try ImageConverter.convert(url, to: target) }
        }
    }
}
