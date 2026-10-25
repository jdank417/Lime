//
//  MetadataTool.swift
//  Lime
//

import AVFoundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Reads, edits and strips metadata for photos, audio, video and PDFs. Edits are saved as a copy.
nonisolated enum MetadataTool {
    struct Row: Identifiable, Sendable {
        var id: String { group + "." + key }
        let group: String
        let key: String
        let value: String
    }

    struct Field: Identifiable, Sendable {
        var id: String { key }
        let key: String
        let label: String
        var value: String
    }

    struct Info: Sendable {
        var rows: [Row]
        var fields: [Field]
        var hasLocation: Bool
    }

    static func read(_ url: URL) async throws -> Info {
        switch FileKind.of(url) {
        case .image: return try readImage(url)
        case .pdf: return try readPDF(url)
        case .audio, .video: return try await readMedia(url)
        default: throw LimeError.failed("Lime can't read metadata from this kind of file")
        }
    }

    /// `fields` maps Field.key to its new value.
    static func save(_ url: URL, fields: [String: String], removeLocation: Bool) async throws -> URL {
        switch FileKind.of(url) {
        case .image: return try saveImage(url, fields: fields, removeLocation: removeLocation)
        case .pdf: return try savePDF(url, fields: fields)
        default: return try await saveMedia(url, fields: fields, strip: removeLocation)
        }
    }

    static func strip(_ url: URL) async throws -> URL {
        switch FileKind.of(url) {
        case .image: return try ImageConverter.edit(url, .stripMetadata)
        case .pdf:
            guard let document = PDFDocument(url: url) else { throw LimeError.unreadable(url.lastPathComponent) }
            document.documentAttributes = [:]
            let out = Output.url(for: url, ext: "pdf", suffix: "no metadata")
            guard document.write(to: out) else { throw LimeError.failed("Couldn't save the PDF") }
            return out
        default: return try await exportMedia(url, items: [], suffix: "no metadata", filter: true)
        }
    }

    // MARK: Images

    private static let tiff = kCGImagePropertyTIFFDictionary as String
    private static let iptc = kCGImagePropertyIPTCDictionary as String

    private static func readImage(_ url: URL) throws -> Info {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { throw LimeError.unreadable(url.lastPathComponent) }

        var rows: [Row] = []
        for (key, value) in properties {
            if let group = value as? [String: Any] {
                let name = key.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                rows += group.map { Row(group: name, key: $0.key, value: describe($0.value)) }
            } else {
                rows.append(Row(group: "Image", key: key, value: describe(value)))
            }
        }
        let tiffInfo = properties[tiff] as? [String: Any] ?? [:]
        let iptcInfo = properties[iptc] as? [String: Any] ?? [:]
        // Each field lives in TIFF/EXIF or IPTC depending on the app that wrote it; take whichever is set.
        func either(_ tiffKey: CFString, _ iptcKey: CFString) -> String {
            if let text = tiffInfo[tiffKey as String] as? String, !text.isEmpty { return text }
            if let list = iptcInfo[iptcKey as String] as? [String] { return list.joined(separator: ", ") }
            return iptcInfo[iptcKey as String] as? String ?? ""
        }
        let fields = [
            Field(key: "title", label: "Title", value: iptcInfo[kCGImagePropertyIPTCObjectName as String] as? String ?? ""),
            Field(key: "description", label: "Description", value: either(kCGImagePropertyTIFFImageDescription, kCGImagePropertyIPTCCaptionAbstract)),
            Field(key: "artist", label: "Artist", value: either(kCGImagePropertyTIFFArtist, kCGImagePropertyIPTCByline)),
            Field(key: "copyright", label: "Copyright", value: either(kCGImagePropertyTIFFCopyright, kCGImagePropertyIPTCCopyrightNotice)),
            Field(key: "keywords", label: "Keywords",
                  value: (iptcInfo[kCGImagePropertyIPTCKeywords as String] as? [String])?.joined(separator: ", ") ?? ""),
        ]
        return Info(rows: rows.sorted { ($0.group, $0.key) < ($1.group, $1.key) }, fields: fields,
                    hasLocation: properties[kCGImagePropertyGPSDictionary as String] != nil)
    }

    private static func saveImage(_ url: URL, fields: [String: String], removeLocation: Bool) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source) else {
            throw LimeError.unreadable(url.lastPathComponent)
        }
        let out = Output.url(for: url, ext: url.pathExtension, suffix: "metadata")
        guard let destination = CGImageDestinationCreateWithURL(out as CFURL, type, 1, nil) else {
            throw LimeError.failed("Can't save this format")
        }
        let keywords = (fields["keywords"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var properties: [String: Any] = [
            tiff: [
                kCGImagePropertyTIFFImageDescription as String: fields["description"] ?? "",
                kCGImagePropertyTIFFArtist as String: fields["artist"] ?? "",
                kCGImagePropertyTIFFCopyright as String: fields["copyright"] ?? "",
            ],
            iptc: [
                kCGImagePropertyIPTCObjectName as String: fields["title"] ?? "",
                kCGImagePropertyIPTCCaptionAbstract as String: fields["description"] ?? "",
                kCGImagePropertyIPTCByline as String: [fields["artist"] ?? ""],
                kCGImagePropertyIPTCCopyrightNotice as String: fields["copyright"] ?? "",
                kCGImagePropertyIPTCKeywords as String: keywords,
            ],
            kCGImageDestinationLossyCompressionQuality as String: 1.0,
        ]
        if removeLocation { properties[kCGImagePropertyGPSDictionary as String] = kCFNull }
        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw LimeError.failed("Couldn't save the photo") }
        return out
    }

    // MARK: PDF

    private static func readPDF(_ url: URL) throws -> Info {
        guard let document = PDFDocument(url: url) else { throw LimeError.unreadable(url.lastPathComponent) }
        let attributes = document.documentAttributes ?? [:]
        let rows = attributes.map { Row(group: "PDF", key: "\($0.key)", value: describe($0.value)) }
            + [Row(group: "PDF", key: "Pages", value: "\(document.pageCount)")]
        func text(_ key: PDFDocumentAttribute) -> String {
            if let list = attributes[key] as? [String] { return list.joined(separator: ", ") }
            return attributes[key] as? String ?? ""
        }
        return Info(rows: rows.sorted { $0.key < $1.key }, fields: [
            Field(key: "title", label: "Title", value: text(.titleAttribute)),
            Field(key: "author", label: "Author", value: text(.authorAttribute)),
            Field(key: "subject", label: "Subject", value: text(.subjectAttribute)),
            Field(key: "keywords", label: "Keywords", value: text(.keywordsAttribute)),
        ], hasLocation: false)
    }

    private static func savePDF(_ url: URL, fields: [String: String]) throws -> URL {
        guard let document = PDFDocument(url: url) else { throw LimeError.unreadable(url.lastPathComponent) }
        var attributes = document.documentAttributes ?? [:]
        attributes[PDFDocumentAttribute.titleAttribute] = fields["title"] ?? ""
        attributes[PDFDocumentAttribute.authorAttribute] = fields["author"] ?? ""
        attributes[PDFDocumentAttribute.subjectAttribute] = fields["subject"] ?? ""
        attributes[PDFDocumentAttribute.keywordsAttribute] = (fields["keywords"] ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        document.documentAttributes = attributes
        let out = Output.url(for: url, ext: "pdf", suffix: "metadata")
        guard document.write(to: out) else { throw LimeError.failed("Couldn't save the PDF") }
        return out
    }

    // MARK: Audio & video

    private static let mediaKeys: [(key: String, label: String, common: AVMetadataKey)] = [
        ("title", "Title", .commonKeyTitle),
        ("artist", "Artist", .commonKeyArtist),
        ("album", "Album", .commonKeyAlbumName),
        ("description", "Description", .commonKeyDescription),
    ]

    private static func readMedia(_ url: URL) async throws -> Info {
        let asset = AVURLAsset(url: url)
        let (duration, common, all) = try await asset.load(.duration, .commonMetadata, .metadata)
        var rows = [Row(group: "File", key: "Duration", value: String(format: "%.2f s", duration.seconds))]
        if let track = try await asset.loadTracks(withMediaType: .video).first {
            let size = try await track.load(.naturalSize)
            rows.append(Row(group: "File", key: "Video size", value: "\(Int(size.width)) × \(Int(size.height))"))
        }
        var hasLocation = false
        for item in all {
            let key = item.commonKey?.rawValue ?? item.identifier?.rawValue ?? "?"
            if item.commonKey == .commonKeyLocation { hasLocation = true }
            rows.append(Row(group: item.keySpace?.rawValue ?? "Metadata", key: key, value: try await value(of: item)))
        }
        var fields: [Field] = []
        for entry in mediaKeys {
            let match = common.first { $0.commonKey == entry.common }
            let text = if let match { try await value(of: match) } else { "" }
            fields.append(Field(key: entry.key, label: entry.label, value: text))
        }
        return Info(rows: rows, fields: fields, hasLocation: hasLocation)
    }

    private static func saveMedia(_ url: URL, fields: [String: String], strip: Bool) async throws -> URL {
        let items: [AVMetadataItem] = mediaKeys.compactMap { entry in
            guard let text = fields[entry.key], !text.isEmpty else { return nil }
            let item = AVMutableMetadataItem()
            item.keySpace = .common
            item.key = entry.common as NSString
            item.value = text as NSString
            item.extendedLanguageTag = "und"
            return item
        }
        return try await exportMedia(url, items: items, suffix: "metadata", filter: strip)
    }

    /// Re-wraps the file with only `items` as metadata. Video and M4A copy straight across; other audio becomes M4A.
    private static func exportMedia(_ url: URL, items: [AVMetadataItem], suffix: String, filter: Bool) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let isVideo = !(try await asset.loadTracks(withMediaType: .video)).isEmpty
        let fileType: AVFileType, ext: String, preset: String
        if isVideo {
            (fileType, ext) = MediaConverter.container(for: url)
            preset = AVAssetExportPresetPassthrough
        } else {
            (fileType, ext) = (.m4a, "m4a")
            preset = normalizedExtension(of: url) == "m4a" ? AVAssetExportPresetPassthrough : AVAssetExportPresetAppleM4A
        }
        return try await MediaConverter.export(asset, source: url, preset: preset, fileType: fileType, ext: ext, suffix: suffix) {
            $0.metadata = items
            if filter { $0.metadataItemFilter = .forSharing() }
        }
    }

    private static func value(of item: AVMetadataItem) async throws -> String {
        if let text = try await item.load(.stringValue) { return text }
        if let date = try await item.load(.dateValue) { return date.formatted() }
        if let number = try await item.load(.numberValue) { return number.stringValue }
        return "(data)"
    }

    private static func describe(_ value: Any) -> String {
        switch value {
        case let list as [Any]: list.map(describe).joined(separator: ", ")
        case let date as Date: date.formatted()
        default: "\(value)"
        }
    }
}
