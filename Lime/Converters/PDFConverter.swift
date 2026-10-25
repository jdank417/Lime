//
//  PDFConverter.swift
//  Lime
//

import AppKit
import PDFKit

nonisolated enum PDFConverter {
    /// One image per page. A single page lands next to the PDF; several go into a folder.
    static func toImages(_ url: URL, target: ImageConverter.Target) throws -> URL {
        let document = try open(url)
        let base = Output.baseName(of: url)
        if document.pageCount == 1, let page = document.page(at: 0) {
            let out = Output.url(for: url, ext: target.ext)
            try ImageConverter.write(render(page), to: out, type: target.type)
            return out
        }
        let folder = Output.url(in: url.deletingLastPathComponent(), base: base, ext: "", suffix: target.label)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let out = folder.appendingPathComponent("\(base) \(index + 1).\(target.ext)")
            try ImageConverter.write(render(page), to: out, type: target.type)
        }
        return folder
    }

    static func toText(_ url: URL) throws -> URL {
        let text = try open(url).string ?? ""
        let out = Output.url(for: url, ext: "txt")
        try text.write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    static func attributedText(_ url: URL) throws -> NSAttributedString {
        try open(url).selectionForEntireDocument?.attributedString ?? NSAttributedString()
    }

    static func merge(_ urls: [URL]) throws -> URL {
        let merged = PDFDocument()
        for url in urls {
            let document = try open(url)
            for index in 0..<document.pageCount {
                if let page = document.page(at: index)?.copy() as? PDFPage {
                    merged.insert(page, at: merged.pageCount)
                }
            }
        }
        let out = Output.url(in: urls[0].deletingLastPathComponent(), base: "Merged", ext: "pdf")
        try save(merged, to: out)
        return out
    }

    static func split(_ url: URL) throws -> URL {
        let document = try open(url)
        let base = Output.baseName(of: url)
        let folder = Output.url(in: url.deletingLastPathComponent(), base: base, ext: "", suffix: "pages")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index)?.copy() as? PDFPage else { continue }
            let single = PDFDocument()
            single.insert(page, at: 0)
            try save(single, to: folder.appendingPathComponent("\(base) \(index + 1).pdf"))
        }
        return folder
    }

    static func rotate(_ url: URL) throws -> URL {
        let document = try open(url)
        for index in 0..<document.pageCount {
            if let page = document.page(at: index) { page.rotation = (page.rotation + 90) % 360 }
        }
        let out = Output.url(for: url, ext: "pdf", suffix: "rotated")
        try save(document, to: out)
        return out
    }

    struct PageChoice: Sendable {
        /// Index in the original document.
        let index: Int
        /// Degrees added to the page's rotation.
        let rotation: Int
    }

    /// Rebuilds the PDF with pages in a new order, some rotated or left out.
    static func reorganize(_ url: URL, pages: [PageChoice]) throws -> URL {
        let source = try open(url)
        let result = PDFDocument()
        for choice in pages {
            guard let page = source.page(at: choice.index)?.copy() as? PDFPage else { continue }
            page.rotation = (page.rotation + choice.rotation) % 360
            result.insert(page, at: result.pageCount)
        }
        guard result.pageCount > 0 else { throw LimeError.failed("There are no pages left") }
        let out = Output.url(for: url, ext: "pdf", suffix: "reorganized")
        try save(result, to: out)
        return out
    }

    static func thumbnails(_ url: URL, size: CGFloat) throws -> [NSImage] {
        let document = try open(url)
        return (0..<document.pageCount).compactMap { document.page(at: $0)?.thumbnail(of: NSSize(width: size, height: size), for: .cropBox) }
    }

    static func compress(_ url: URL) throws -> URL {
        let document = try open(url)
        let out = Output.url(for: url, ext: "pdf", suffix: "compressed")
        let options: [PDFDocumentWriteOption: Any] = [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true]
        guard document.write(to: out, withOptions: options) else { throw LimeError.failed("Couldn't save the PDF") }
        return out
    }

    // MARK: Plumbing

    private static func open(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw LimeError.unreadable(url.lastPathComponent) }
        if document.isLocked { throw LimeError.failed("\(url.lastPathComponent) is password protected") }
        return document
    }

    private static func save(_ document: PDFDocument, to url: URL) throws {
        guard document.write(to: url) else { throw LimeError.failed("Couldn't save the PDF") }
    }

    /// Renders at 2× (144 dpi) on white, honoring page rotation.
    private static func render(_ page: PDFPage, scale: CGFloat = 2) throws -> CGImage {
        let box = page.bounds(for: .mediaBox)
        let size = page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw LimeError.failed("Couldn't render the page") }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        page.transform(ctx, for: .mediaBox)
        page.draw(with: .mediaBox, to: ctx)
        guard let image = ctx.makeImage() else { throw LimeError.failed("Couldn't render the page") }
        return image
    }
}
