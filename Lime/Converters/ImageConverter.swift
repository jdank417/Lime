//
//  ImageConverter.swift
//  Lime
//

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import PDFKit
import UniformTypeIdentifiers

nonisolated enum ImageConverter {
    struct Target: Sendable {
        let label: String
        let type: UTType
        let ext: String
    }

    /// Formats this Mac can write, in wheel order. PDF is handled by PDFKit rather than ImageIO.
    static let targets: [Target] = {
        let writable = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        let raster: [Target] = [
            .init(label: "PNG", type: .png, ext: "png"),
            .init(label: "JPG", type: .jpeg, ext: "jpg"),
            .init(label: "HEIC", type: .heic, ext: "heic"),
            .init(label: "AVIF", type: UTType("public.avif") ?? .heic, ext: "avif"),
            .init(label: "WebP", type: .webP, ext: "webp"),
            .init(label: "TIFF", type: .tiff, ext: "tiff"),
            .init(label: "GIF", type: .gif, ext: "gif"),
            .init(label: "BMP", type: .bmp, ext: "bmp"),
        ]
        return raster.filter { writable.contains($0.type.identifier) } + [.init(label: "PDF", type: .pdf, ext: "pdf")]
    }()

    static var png: Target { targets[0] }
    static var jpeg: Target { targets.first { $0.type == .jpeg } ?? png }

    enum Edit: Sendable {
        case halfSize, rotate, flip, grayscale, stripMetadata, compress
    }

    private static let context = CIContext()

    // MARK: Actions

    static func convert(_ url: URL, to target: Target) throws -> URL {
        let out = Output.url(for: url, ext: target.ext)
        try write(render(load(url)), to: out, type: target.type)
        return out
    }

    static func edit(_ url: URL, _ edit: Edit) throws -> URL {
        var image = try load(url)
        var target = sameFormat(as: url)
        var quality = 0.9
        let suffix: String
        switch edit {
        case .halfSize:
            let filter = CIFilter.lanczosScaleTransform()
            filter.inputImage = image
            filter.scale = 0.5
            filter.aspectRatio = 1
            image = filter.outputImage ?? image
            suffix = "half size"
        case .rotate:
            image = image.oriented(.right)
            suffix = "rotated"
        case .flip:
            image = image.oriented(.upMirrored)
            suffix = "flipped"
        case .grayscale:
            let filter = CIFilter.colorControls()
            filter.inputImage = image
            filter.saturation = 0
            image = filter.outputImage ?? image
            suffix = "grayscale"
        case .stripMetadata:
            // Re-encoding through Core Image already drops EXIF, GPS and the rest.
            suffix = "no metadata"
        case .compress:
            target = jpeg
            quality = 0.55
            suffix = "compressed"
        }
        let out = Output.url(for: url, ext: target.ext, suffix: suffix)
        try write(render(image), to: out, type: target.type, quality: quality)
        return out
    }

    static func combineIntoPDF(_ urls: [URL]) throws -> URL {
        let document = PDFDocument()
        for url in urls {
            if let page = page(for: try render(load(url))) {
                document.insert(page, at: document.pageCount)
            }
        }
        let out = Output.url(in: urls[0].deletingLastPathComponent(), base: "Combined", ext: "pdf")
        guard document.write(to: out) else { throw LimeError.failed("Couldn't save the PDF") }
        return out
    }

    // MARK: Plumbing

    static func load(_ url: URL) throws -> CIImage {
        if let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) { return image }
        // NSImage covers a few formats Core Image can't open, like SVG.
        if let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CIImage(cgImage: image)
        }
        throw LimeError.unreadable(url.lastPathComponent)
    }

    static func render(_ image: CIImage) throws -> CGImage {
        guard let cgImage = context.createCGImage(image, from: image.extent.integral) else {
            throw LimeError.failed("Couldn't render the image")
        }
        return cgImage
    }

    static func write(_ image: CGImage, to url: URL, type: UTType, quality: Double = 0.9) throws {
        if type == .pdf {
            let document = PDFDocument()
            if let page = page(for: image) { document.insert(page, at: 0) }
            guard document.write(to: url) else { throw LimeError.failed("Couldn't save the PDF") }
            return
        }
        // JPEG and BMP have no alpha; without this, transparent areas turn black.
        let image = [UTType.jpeg, .bmp].contains(type) ? try flattened(image) : image
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw LimeError.failed("Can't write \(type.preferredFilenameExtension?.uppercased() ?? "that format")")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw LimeError.failed("Couldn't save the image") }
    }

    private static func page(for image: CGImage) -> PDFPage? {
        PDFPage(image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
    }

    private static func flattened(_ image: CGImage) throws -> CGImage {
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw LimeError.failed("Couldn't render the image") }
        ctx.setFillColor(.white)
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        guard let result = ctx.makeImage() else { throw LimeError.failed("Couldn't render the image") }
        return result
    }

    /// Edits keep the original format when we can write it, otherwise fall back to PNG.
    static func sameFormat(as url: URL) -> Target {
        let ext = normalizedExtension(of: url)
        return targets.first { $0.ext == ext && $0.type != .pdf } ?? png
    }
}
