//
//  ImageTools.swift
//  Lime
//

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

/// sRGB color that can cross threads, with SwiftUI and Core Graphics forms.
nonisolated struct RGBA: Hashable, Sendable {
    var r: Double, g: Double, b: Double, a: Double = 1

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

/// The work behind the photo tools. Everything here is plain functions so tests can drive it.
nonisolated enum ImageTools {
    // MARK: Previews

    /// The image scaled down for live previews.
    static func previewImage(_ url: URL, maxDimension: CGFloat = 1400) throws -> CIImage {
        let full = try ImageConverter.load(url)
        let longest = max(full.extent.width, full.extent.height)
        guard longest > maxDimension else { return full }
        let scale = maxDimension / longest
        return full.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    static func nsImage(_ image: CIImage) -> NSImage? {
        guard let cgImage = try? ImageConverter.render(image) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Saves next to the original as "name (suffix).ext", keeping the format when Lime can write it.
    static func saveEdited(_ image: CGImage, source: URL, suffix: String, forcePNG: Bool = false) throws -> URL {
        let target = forcePNG ? ImageConverter.png : ImageConverter.sameFormat(as: source)
        let out = Output.url(for: source, ext: target.ext, suffix: suffix)
        try ImageConverter.write(image, to: out, type: target.type)
        return out
    }

    // MARK: Adjust

    struct Adjustments: Equatable, Sendable {
        var exposure = 0.0      // EV, -2...2
        var brightness = 0.0    // -100...100
        var contrast = 0.0      // -100...100
        var highlights = 0.0    // -100...100
        var shadows = 0.0       // -100...100
        var saturation = 0.0    // -100...100
        var warmth = 0.0        // -100...100
    }

    static func adjust(_ image: CIImage, _ a: Adjustments) -> CIImage {
        var out = image
        if a.exposure != 0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = out
            filter.ev = Float(a.exposure)
            out = filter.outputImage ?? out
        }
        if a.brightness != 0 || a.contrast != 0 || a.saturation != 0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = out
            filter.brightness = Float(a.brightness / 100 * 0.35)
            filter.contrast = Float(1 + a.contrast / 100 * 0.5)
            filter.saturation = Float(1 + a.saturation / 100)
            out = filter.outputImage ?? out
        }
        if a.highlights < 0 || a.shadows != 0 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = out
            filter.highlightAmount = Float(1 + min(a.highlights, 0) / 100)
            filter.shadowAmount = Float(a.shadows / 100)
            out = filter.outputImage ?? out
        }
        if a.highlights > 0 {
            // The highlight filter can only pull highlights down; lift them with a tone curve instead.
            let filter = CIFilter.toneCurve()
            filter.inputImage = out
            filter.point0 = CGPoint(x: 0, y: 0)
            filter.point1 = CGPoint(x: 0.25, y: 0.25)
            filter.point2 = CGPoint(x: 0.5, y: 0.5)
            filter.point3 = CGPoint(x: 0.75, y: 0.75 + 0.15 * a.highlights / 100)
            filter.point4 = CGPoint(x: 1, y: 1)
            out = filter.outputImage ?? out
        }
        if a.warmth != 0 {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = out
            filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(x: 6500 + a.warmth * 25, y: 0)
            out = filter.outputImage ?? out
        }
        return out.cropped(to: image.extent)
    }

    static func applyAdjustments(_ url: URL, _ adjustments: Adjustments) throws -> URL {
        try saveEdited(ImageConverter.render(adjust(ImageConverter.load(url), adjustments)), source: url, suffix: "edited")
    }

    // MARK: Crop

    /// `rect` is normalized with a top-left origin, as the crop overlay draws it.
    static func crop(_ image: CIImage, to rect: CGRect) -> CIImage {
        let e = image.extent
        let pixels = CGRect(x: e.minX + rect.minX * e.width, y: e.minY + (1 - rect.maxY) * e.height,
                            width: rect.width * e.width, height: rect.height * e.height).integral.intersection(e)
        return image.cropped(to: pixels).transformed(by: CGAffineTransform(translationX: -pixels.minX, y: -pixels.minY))
    }

    static func applyCrop(_ url: URL, rect: CGRect) throws -> URL {
        try saveEdited(ImageConverter.render(crop(ImageConverter.load(url), to: rect)), source: url, suffix: "cropped")
    }

    static func rotate(_ url: URL) throws -> URL {
        try ImageConverter.edit(url, .rotate)
    }

    // MARK: Redact

    enum RedactStyle: String, CaseIterable, Sendable {
        case black = "Black Box", pixelate = "Pixelate", blur = "Blur"
    }

    static func redact(_ image: CIImage, rects: [CGRect], style: RedactStyle) -> CIImage {
        let e = image.extent
        let longest = max(e.width, e.height)
        let cover: CIImage
        switch style {
        case .black:
            cover = CIImage(color: CIColor(red: 0, green: 0, blue: 0))
        case .pixelate:
            let filter = CIFilter.pixellate()
            filter.inputImage = image.clampedToExtent()
            filter.scale = Float(max(8, longest / 45))
            filter.center = CGPoint(x: e.midX, y: e.midY)
            cover = filter.outputImage ?? image
        case .blur:
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = image.clampedToExtent()
            filter.radius = Float(max(6, longest / 50))
            cover = filter.outputImage ?? image
        }
        var out = image
        for rect in rects {
            let pixels = CGRect(x: e.minX + rect.minX * e.width, y: e.minY + (1 - rect.maxY) * e.height,
                                width: rect.width * e.width, height: rect.height * e.height)
            out = cover.cropped(to: pixels).composited(over: out)
        }
        return out.cropped(to: e)
    }

    static func applyRedaction(_ url: URL, rects: [CGRect], style: RedactStyle) throws -> URL {
        let image = try ImageConverter.load(url)
        return try saveEdited(ImageConverter.render(redact(image, rects: rects, style: style)), source: url, suffix: "redacted")
    }

    // MARK: Annotate

    struct Mark: Identifiable, Sendable {
        enum Kind: String, CaseIterable, Sendable {
            case pen, highlighter, arrow, box, text
        }

        var id = UUID()
        var kind: Kind
        /// Normalized, top-left origin.
        var points: [CGPoint]
        var color: RGBA
        /// Stroke width as a fraction of the image width, so it scales with the image.
        var width: CGFloat
        var text = ""

        func strokeWidth(in size: CGSize) -> CGFloat {
            width * size.width * (kind == .highlighter ? 3 : 1)
        }

        func fontSize(in size: CGSize) -> CGFloat {
            max(10, width * size.width * 5)
        }

        /// The stroke for every kind except text, in a top-left-origin space of `size`.
        func path(in size: CGSize) -> CGPath {
            let pts = points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            let path = CGMutablePath()
            guard let first = pts.first else { return path }
            switch kind {
            case .pen, .highlighter:
                path.move(to: first)
                for point in pts.dropFirst() { path.addLine(to: point) }
                if pts.count == 1 { path.addLine(to: first) }
            case .arrow:
                let end = pts.last ?? first
                path.move(to: first)
                path.addLine(to: end)
                let angle = atan2(end.y - first.y, end.x - first.x)
                let head = max(strokeWidth(in: size) * 4, 10)
                for side: CGFloat in [-1, 1] {
                    let a: CGFloat = angle + .pi - side * 0.45
                    path.move(to: end)
                    path.addLine(to: CGPoint(x: end.x + head * cos(a), y: end.y + head * sin(a)))
                }
            case .box:
                let end = pts.last ?? first
                path.addRect(CGRect(x: min(first.x, end.x), y: min(first.y, end.y),
                                    width: abs(end.x - first.x), height: abs(end.y - first.y)))
            case .text:
                break
            }
            return path
        }
    }

    static func annotate(_ base: CGImage, marks: [Mark]) throws -> CGImage {
        let size = CGSize(width: base.width, height: base.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw LimeError.failed("Couldn't draw on the image") }
        ctx.draw(base, in: CGRect(origin: .zero, size: size))
        // Marks are stored top-left-origin, like the screen.
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for mark in marks {
            if mark.kind == .text {
                guard let point = mark.points.first, !mark.text.isEmpty else { continue }
                let previous = NSGraphicsContext.current
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                let font = NSFont.systemFont(ofSize: mark.fontSize(in: size), weight: .bold)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor(cgColor: mark.color.cgColor) ?? .black,
                ]
                NSAttributedString(string: mark.text, attributes: attributes)
                    // Vertically centered on the point, matching the editor's preview.
                    .draw(at: CGPoint(x: point.x * size.width, y: point.y * size.height - (font.ascender - font.descender) / 2))
                NSGraphicsContext.current = previous
                continue
            }
            ctx.saveGState()
            ctx.setLineWidth(mark.strokeWidth(in: size))
            var color = mark.color
            if mark.kind == .highlighter {
                color.a = 0.4
                ctx.setBlendMode(.multiply)
            }
            ctx.setStrokeColor(color.cgColor)
            ctx.addPath(mark.path(in: size))
            ctx.strokePath()
            ctx.restoreGState()
        }
        guard let result = ctx.makeImage() else { throw LimeError.failed("Couldn't draw on the image") }
        return result
    }

    static func applyAnnotations(_ url: URL, marks: [Mark]) throws -> URL {
        let base = try ImageConverter.render(ImageConverter.load(url))
        return try saveEdited(annotate(base, marks: marks), source: url, suffix: "annotated")
    }

    // MARK: Background

    struct Backdrop: Equatable, Sendable {
        /// One color is solid; more make a diagonal gradient.
        var colors: [RGBA]
        var padding = 0.12       // fraction of the longer side
        var cornerRadius = 0.04  // fraction of the shorter side
        var shadow = true
    }

    static func addBackground(_ image: CGImage, _ backdrop: Backdrop) throws -> CGImage {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let pad = (backdrop.padding * max(w, h)).rounded()
        let canvas = CGSize(width: w + pad * 2, height: h + pad * 2)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw LimeError.failed("Couldn't make the background") }

        let full = CGRect(origin: .zero, size: canvas)
        if backdrop.colors.count > 1, let gradient = CGGradient(colorsSpace: space, colors: backdrop.colors.map(\.cgColor) as CFArray,
                                                              locations: nil) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: canvas.height), end: CGPoint(x: canvas.width, y: 0), options: [])
        } else {
            ctx.setFillColor((backdrop.colors.first ?? RGBA(1, 1, 1)).cgColor)
            ctx.fill(full)
        }

        let frame = CGRect(x: pad, y: pad, width: w, height: h)
        let radius = backdrop.cornerRadius * min(w, h)
        if backdrop.shadow && pad > 0 {
            ctx.setShadow(offset: CGSize(width: 0, height: -pad * 0.12), blur: pad * 0.45, color: CGColor(gray: 0, alpha: 0.35))
        }
        // Drawing inside a transparency layer makes the shadow follow the rounded, possibly transparent image.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        ctx.draw(image, in: frame)
        ctx.endTransparencyLayer()
        guard let result = ctx.makeImage() else { throw LimeError.failed("Couldn't make the background") }
        return result
    }

    static func applyBackground(_ url: URL, _ backdrop: Backdrop) throws -> URL {
        let base = try ImageConverter.render(ImageConverter.load(url))
        return try saveEdited(addBackground(base, backdrop), source: url, suffix: "background", forcePNG: true)
    }

    // MARK: Compress

    static func encode(_ image: CGImage, as target: ImageConverter.Target, quality: Double) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, target.type.identifier as CFString, 1, nil) else {
            throw LimeError.failed("Can't write \(target.label)")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw LimeError.failed("Couldn't compress the image") }
        return data as Data
    }

    static func scaled(_ image: CIImage, by scale: Double) -> CIImage {
        guard scale < 0.999 else { return image }
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(scale)
        filter.aspectRatio = 1
        return filter.outputImage ?? image
    }

    /// JPEG/HEIC/AVIF at a quality and size.
    static func compressed(_ url: URL, as target: ImageConverter.Target, quality: Double, scale: Double) throws -> Data {
        let image = try ImageConverter.render(scaled(ImageConverter.load(url), by: scale))
        let flat = [UTType.jpeg].contains(target.type) ? try flatten(image) : image
        return try encode(flat, as: target, quality: quality)
    }

    /// Lowers quality (then size, if needed) until the file fits in `maxBytes`.
    static func compressed(_ url: URL, as target: ImageConverter.Target, maxBytes: Int) throws -> Data {
        var scale = 1.0
        while true {
            let image = try ImageConverter.render(scaled(ImageConverter.load(url), by: scale))
            let flat = target.type == .jpeg ? try flatten(image) : image
            var low = 0.05, high = 0.95
            var best: Data?
            for _ in 0..<7 {
                let mid = (low + high) / 2
                let data = try encode(flat, as: target, quality: mid)
                if data.count <= maxBytes { best = data; low = mid } else { high = mid }
            }
            if let best { return best }
            if let data = try? encode(flat, as: target, quality: 0.05), data.count <= maxBytes { return data }
            scale *= 0.75
            if scale < 0.05 { throw LimeError.failed("Can't get it that small") }
        }
    }

    static func saveCompressed(_ data: Data, source: URL, target: ImageConverter.Target) throws -> URL {
        let out = Output.url(for: source, ext: target.ext, suffix: "compressed")
        try data.write(to: out)
        return out
    }

    private static func flatten(_ image: CGImage) throws -> CGImage {
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw LimeError.failed("Couldn't render the image") }
        ctx.setFillColor(.white)
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        guard let result = ctx.makeImage() else { throw LimeError.failed("Couldn't render the image") }
        return result
    }

    // MARK: QR codes, SVG, collage

    static func qrCodes(in url: URL) throws -> [String] {
        let image = try ImageConverter.load(url)
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return detector?.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString } ?? []
    }

    /// An SVG that wraps the picture as embedded PNG, so it opens anywhere SVG is expected.
    static func svg(_ url: URL) throws -> URL {
        let image = try ImageConverter.render(ImageConverter.load(url))
        let png = try encode(image, as: ImageConverter.png, quality: 1).base64EncodedString()
        let w = image.width, h = image.height
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(w)" height="\(h)" viewBox="0 0 \(w) \(h)">
          <image width="\(w)" height="\(h)" href="data:image/png;base64,\(png)"/>
        </svg>
        """
        let out = Output.url(for: url, ext: "svg")
        try svg.write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    /// A white grid of square tiles, each image filling its tile.
    static func collage(_ urls: [URL]) throws -> URL {
        let columns = Int(ceil(sqrt(Double(urls.count))))
        let rows = Int(ceil(Double(urls.count) / Double(columns)))
        let cell: CGFloat = 900, gap: CGFloat = 24
        let canvas = CGSize(width: CGFloat(columns) * (cell + gap) + gap, height: CGFloat(rows) * (cell + gap) + gap)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw LimeError.failed("Couldn't make the collage") }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(origin: .zero, size: canvas))

        for (index, url) in urls.enumerated() {
            let image = try ImageConverter.render(ImageConverter.load(url))
            let column = index % columns, row = index / columns
            let tile = CGRect(x: gap + CGFloat(column) * (cell + gap),
                              y: canvas.height - gap - cell - CGFloat(row) * (cell + gap), width: cell, height: cell)
            let scale = max(cell / CGFloat(image.width), cell / CGFloat(image.height))
            let drawn = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 18, cornerHeight: 18, transform: nil))
            ctx.clip()
            ctx.draw(image, in: CGRect(x: tile.midX - drawn.width / 2, y: tile.midY - drawn.height / 2,
                                       width: drawn.width, height: drawn.height))
            ctx.restoreGState()
        }
        guard let result = ctx.makeImage() else { throw LimeError.failed("Couldn't make the collage") }
        let out = Output.url(in: urls[0].deletingLastPathComponent(), base: "Collage", ext: "png")
        try ImageConverter.write(result, to: out, type: .png)
        return out
    }
}
