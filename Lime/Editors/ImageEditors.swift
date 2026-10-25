//
//  ImageEditors.swift
//  Lime
//

import AppKit
import CoreImage
import SwiftUI

// MARK: - Edit Photo

struct AdjustEditor: View {
    let urls: [URL]
    @ObservedObject var session: EditorSession
    @State private var base: CIImage?
    @State private var preview: NSImage?
    @State private var adjustments = ImageTools.Adjustments()

    var body: some View {
        EditorShell(title: "Edit Photo", session: session, onApply: apply) {
            VStack(spacing: 12) {
                PreviewBox {
                    if let preview {
                        Image(nsImage: preview).resizable().scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .frame(height: 300)
                SectionTitle("Light")
                SliderRow(title: "Exposure", value: $adjustments.exposure, range: -2...2) { String(format: "%+.2f EV", $0) }
                SliderRow(title: "Brightness", value: $adjustments.brightness, range: -100...100)
                SliderRow(title: "Contrast", value: $adjustments.contrast, range: -100...100)
                SliderRow(title: "Highlights", value: $adjustments.highlights, range: -100...100)
                SliderRow(title: "Shadows", value: $adjustments.shadows, range: -100...100)
                SectionTitle("Color")
                SliderRow(title: "Saturation", value: $adjustments.saturation, range: -100...100)
                SliderRow(title: "Warmth", value: $adjustments.warmth, range: -100...100)
            }
        } controls: {
            Button("Reset All") { adjustments = .init() }
                .buttonStyle(GlassPillButtonStyle())
            if urls.count > 1 {
                Text("Applies to all \(urls.count) photos").font(.caption.weight(.semibold))
            }
        }
        .task {
            let url = urls[0]
            base = try? await offMain { try ImageTools.previewImage(url) }
            render()
        }
        .onChange(of: adjustments) { render() }
    }

    private func render() {
        guard let base else { return }
        preview = ImageTools.nsImage(ImageTools.adjust(base, adjustments))
    }

    private func apply() {
        let adjustments = adjustments, urls = urls
        session.apply {
            var outputs: [URL] = []
            for url in urls {
                outputs.append(try await offMain { try ImageTools.applyAdjustments(url, adjustments) })
            }
            return outputs
        }
    }
}

// MARK: - Crop

enum CropAspect: String, CaseIterable, Identifiable {
    case free = "Free", original = "Original", square = "1:1", fourThree = "4:3", threeTwo = "3:2"
    case sixteenNine = "16:9", nineSixteen = "9:16", fourFive = "4:5"

    var id: String { rawValue }

    /// Pixel width / height, or nil for free-form.
    func ratio(original: CGSize) -> CGFloat? {
        switch self {
        case .free: nil
        case .original: original.height > 0 ? original.width / original.height : nil
        case .square: 1
        case .fourThree: 4.0 / 3
        case .threeTwo: 3.0 / 2
        case .sixteenNine: 16.0 / 9
        case .nineSixteen: 9.0 / 16
        case .fourFive: 4.0 / 5
        }
    }
}

/// Draggable crop frame over an image, in normalized top-left coordinates.
struct CropOverlay: View {
    @Binding var rect: CGRect
    let pixelSize: CGSize
    /// Pixel width / height to keep, or nil for free-form.
    let ratio: CGFloat?
    var resizable = true
    @State private var dragStart: CGRect?

    private enum Corner: CaseIterable, Identifiable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
        var id: Self { self }
        var isTop: Bool { self == .topLeading || self == .topTrailing }
    }

    /// The same ratio in normalized units, where 1 × 1 is the whole image.
    private var normalizedRatio: CGFloat? {
        guard let ratio, pixelSize.width > 0 else { return nil }
        return ratio * pixelSize.height / pixelSize.width
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let frame = CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
                               width: rect.width * size.width, height: rect.height * size.height)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addRect(frame)
                }
                .fill(.black.opacity(0.5), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                Path { path in
                    for i in 1...2 {
                        let x = frame.minX + frame.width * CGFloat(i) / 3
                        let y = frame.minY + frame.height * CGFloat(i) / 3
                        path.move(to: CGPoint(x: x, y: frame.minY)); path.addLine(to: CGPoint(x: x, y: frame.maxY))
                        path.move(to: CGPoint(x: frame.minX, y: y)); path.addLine(to: CGPoint(x: frame.maxX, y: y))
                    }
                }
                .stroke(.white.opacity(0.45), lineWidth: 0.5)
                .allowsHitTesting(false)

                Rectangle()
                    .strokeBorder(.white, lineWidth: 2)
                    .contentShape(Rectangle())
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .gesture(moveGesture(size))

                if resizable {
                    ForEach(Corner.allCases) { corner in
                        Circle()
                            .fill(.white)
                            .frame(width: 16, height: 16)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .position(point(corner, frame))
                            .gesture(resizeGesture(corner, size))
                    }
                }
            }
        }
    }

    private func point(_ corner: Corner, _ frame: CGRect) -> CGPoint {
        switch corner {
        case .topLeading: CGPoint(x: frame.minX, y: frame.minY)
        case .topTrailing: CGPoint(x: frame.maxX, y: frame.minY)
        case .bottomLeading: CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomTrailing: CGPoint(x: frame.maxX, y: frame.maxY)
        }
    }

    private func moveGesture(_ size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? rect
                dragStart = start
                var moved = start
                moved.origin.x = min(max(start.minX + value.translation.width / size.width, 0), 1 - start.width)
                moved.origin.y = min(max(start.minY + value.translation.height / size.height, 0), 1 - start.height)
                rect = moved
            }
            .onEnded { _ in dragStart = nil }
    }

    private func resizeGesture(_ corner: Corner, _ size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? rect
                dragStart = start
                let dx = value.translation.width / size.width, dy = value.translation.height / size.height
                var minX = start.minX, minY = start.minY, maxX = start.maxX, maxY = start.maxY
                switch corner {
                case .topLeading: minX += dx; minY += dy
                case .topTrailing: maxX += dx; minY += dy
                case .bottomLeading: minX += dx; maxY += dy
                case .bottomTrailing: maxX += dx; maxY += dy
                }
                var next = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                if let normalizedRatio {
                    let height = next.width / normalizedRatio
                    if corner.isTop { next.origin.y = maxY - height }
                    next.size.height = height
                }
                let epsilon = 0.0005
                guard next.width >= 0.05, next.height >= 0.05, next.minX >= -epsilon, next.minY >= -epsilon,
                      next.maxX <= 1 + epsilon, next.maxY <= 1 + epsilon else { return }
                rect = next
            }
            .onEnded { _ in dragStart = nil }
    }

    /// The biggest centered frame with this ratio.
    static func fullRect(ratio: CGFloat?, pixelSize: CGSize) -> CGRect {
        guard let ratio, pixelSize.width > 0, pixelSize.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let normalized = ratio * pixelSize.height / pixelSize.width
        var width: CGFloat = 1, height = 1 / normalized
        if height > 1 { height = 1; width = normalized }
        return CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }
}

struct CropEditor: View {
    let url: URL
    @ObservedObject var session: EditorSession
    @State private var preview: NSImage?
    @State private var pixelSize = CGSize.zero
    @State private var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var aspect = CropAspect.free

    var body: some View {
        EditorShell(title: "Crop", session: session, onApply: apply) {
            VStack(spacing: 14) {
                PreviewBox {
                    GeometryReader { geometry in
                        let fit = fittedRect(pixelSize, in: geometry.size)
                        if let preview {
                            ZStack {
                                Image(nsImage: preview).resizable()
                                CropOverlay(rect: $rect, pixelSize: pixelSize, ratio: aspect.ratio(original: pixelSize))
                            }
                            .frame(width: fit.width, height: fit.height)
                            .position(x: fit.midX, y: fit.midY)
                        }
                    }
                }
                .frame(height: 400)
                Picker("Aspect", selection: $aspect) {
                    ForEach(CropAspect.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("\(Int(rect.width * pixelSize.width)) × \(Int(rect.height * pixelSize.height)) px")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .onChange(of: aspect) { rect = CropOverlay.fullRect(ratio: aspect.ratio(original: pixelSize), pixelSize: pixelSize) }
        .task {
            let url = url
            let full = try? await offMain { try ImageConverter.load(url).extent.size }
            pixelSize = full ?? .zero
            preview = (try? await offMain { try ImageTools.previewImage(url) }).flatMap(ImageTools.nsImage)
        }
    }

    private func apply() {
        let url = url, rect = rect
        session.apply { [try await offMain { try ImageTools.applyCrop(url, rect: rect) }] }
    }
}

// MARK: - Redact

struct RedactEditor: View {
    let url: URL
    @ObservedObject var session: EditorSession
    @State private var base: CIImage?
    @State private var preview: NSImage?
    @State private var rects: [CGRect] = []
    @State private var draft: CGRect?
    @State private var style = ImageTools.RedactStyle.black

    var body: some View {
        EditorShell(title: "Redact", session: session, canApply: !rects.isEmpty, onApply: apply) {
            VStack(spacing: 14) {
                Picker("Style", selection: $style) {
                    ForEach(ImageTools.RedactStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                PreviewBox {
                    GeometryReader { geometry in
                        let fit = fittedRect(base?.extent.size ?? .zero, in: geometry.size)
                        if let preview {
                            ZStack(alignment: .topLeading) {
                                Image(nsImage: preview).resizable()
                                if let draft {
                                    Rectangle()
                                        .strokeBorder(Theme.limeLight, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                                        .frame(width: draft.width * fit.width, height: draft.height * fit.height)
                                        .offset(x: draft.minX * fit.width, y: draft.minY * fit.height)
                                }
                            }
                            .frame(width: fit.width, height: fit.height)
                            .contentShape(Rectangle())
                            .gesture(drawGesture(fit.size))
                            .position(x: fit.midX, y: fit.midY)
                        }
                    }
                }
                .frame(height: 430)
                Text("Drag over anything you want hidden.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        } controls: {
            Button("Undo") { _ = rects.popLast() }
                .buttonStyle(GlassPillButtonStyle())
                .disabled(rects.isEmpty)
            Button("Clear") { rects.removeAll() }
                .buttonStyle(GlassPillButtonStyle())
                .disabled(rects.isEmpty)
        }
        .task {
            let url = url
            base = try? await offMain { try ImageTools.previewImage(url) }
            render()
        }
        .onChange(of: rects) { render() }
        .onChange(of: style) { render() }
    }

    private func drawGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let a = value.startLocation, b = value.location
                let rect = CGRect(x: min(a.x, b.x) / size.width, y: min(a.y, b.y) / size.height,
                                  width: abs(b.x - a.x) / size.width, height: abs(b.y - a.y) / size.height)
                draft = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            .onEnded { _ in
                if let draft, draft.width > 0.005, draft.height > 0.005 { rects.append(draft) }
                draft = nil
            }
    }

    private func render() {
        guard let base else { return }
        preview = ImageTools.nsImage(ImageTools.redact(base, rects: rects, style: style))
    }

    private func apply() {
        let url = url, rects = rects, style = style
        session.apply { [try await offMain { try ImageTools.applyRedaction(url, rects: rects, style: style) }] }
    }
}

// MARK: - Add BG

private let solidBackdrops: [[RGBA]] = [
    0xFFFFFF, 0x0F170C, 0x7CC822, 0x2F6E12, 0x1E88E5, 0xEC407A, 0x8E44AD, 0xFF9800, 0x263238, 0xECEFF1,
].map { [RGBA(hex: $0)] }

private let gradientBackdrops: [[RGBA]] = [
    [0xC7F06A, 0x2BB673], [0x4FC3F7, 0x1E88E5], [0xFBC2EB, 0xA6C1EE], [0xF6D365, 0xFDA085],
    [0x43E97B, 0x38F9D7], [0x0F2027, 0x2C5364], [0xFF9A9E, 0xFECFEF], [0xA18CD1, 0xFBC2EB],
].map { $0.map(RGBA.init(hex:)) }

struct BackgroundEditor: View {
    let url: URL
    @ObservedObject var session: EditorSession
    @State private var base: CGImage?
    @State private var preview: NSImage?
    @State private var backdrop = ImageTools.Backdrop(colors: gradientBackdrops[0])

    var body: some View {
        EditorShell(title: "Add BG", session: session, onApply: apply) {
            VStack(spacing: 14) {
                PreviewBox {
                    if let preview {
                        Image(nsImage: preview).resizable().scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .frame(height: 320)
                HStack(alignment: .top, spacing: 16) {
                    SectionTitle("Background").frame(width: 96)
                    VStack(alignment: .leading, spacing: 8) {
                        swatchRow(gradientBackdrops)
                        swatchRow(solidBackdrops)
                    }
                }
                SliderRow(title: "Padding", value: $backdrop.padding, range: 0...0.3, defaultValue: 0.12) { "\(Int($0 * 100))%" }
                SliderRow(title: "Corners", value: $backdrop.cornerRadius, range: 0...0.25, defaultValue: 0.04) { "\(Int($0 * 100))%" }
                Toggle("Drop shadow", isOn: $backdrop.shadow)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task {
            let url = url
            base = try? await offMain { try ImageConverter.render(ImageTools.previewImage(url, maxDimension: 900)) }
            await render()
        }
        .task(id: backdrop) { await render() }
    }

    private func swatchRow(_ options: [[RGBA]]) -> some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { colors in
                Button {
                    backdrop.colors = colors
                } label: {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(LinearGradient(colors: colors.map { Color(cgColor: $0.cgColor) },
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 34, height: 34)
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.6), lineWidth: 1))
                        .padding(3)
                        .overlay(RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(Theme.limeDeep, lineWidth: backdrop.colors == colors ? 2.5 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(colors.count > 1 ? "Gradient background" : "Solid background")
            }
        }
    }

    private func render() async {
        guard let base else { return }
        let backdrop = backdrop
        if let image = try? await offMain({ try ImageTools.addBackground(base, backdrop) }) {
            preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }

    private func apply() {
        let url = url, backdrop = backdrop
        session.apply { [try await offMain { try ImageTools.applyBackground(url, backdrop) }] }
    }
}

// MARK: - Compress

struct CompressImageEditor: View {
    let urls: [URL]
    @ObservedObject var session: EditorSession
    @State private var format = ImageConverter.jpeg.ext
    @State private var targetSize = false
    @State private var quality = 0.7
    @State private var scale = 1.0
    @State private var maxMB = 1.0
    @State private var estimate: Int?

    private var formats: [ImageConverter.Target] {
        ImageConverter.targets.filter { ["jpg", "heic", "avif", "png"].contains($0.ext) }
    }

    private var target: ImageConverter.Target {
        formats.first { $0.ext == format } ?? ImageConverter.jpeg
    }

    private var originalBytes: Int {
        (try? urls[0].resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    var body: some View {
        EditorShell(title: "Compress", session: session, onApply: apply) {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("Format")
                Picker("Format", selection: $format) {
                    ForEach(formats, id: \.ext) { Text($0.label).tag($0.ext) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                SectionTitle("Aim for")
                Picker("Mode", selection: $targetSize) {
                    Text("Quality").tag(false)
                    Text("Exact file size").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if targetSize {
                    HStack {
                        Text("At most").frame(width: 96, alignment: .leading)
                        TextField("MB", value: $maxMB, format: .number.precision(.fractionLength(0...2)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        Text("MB per photo")
                        Spacer()
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                } else {
                    if format != "png" {
                        SliderRow(title: "Quality", value: $quality, range: 0.1...1, defaultValue: 0.7) { "\(Int($0 * 100))%" }
                    }
                    SliderRow(title: "Size", value: $scale, range: 0.1...1, defaultValue: 1) { "\(Int($0 * 100))%" }
                }
                Spacer(minLength: 0)
                HStack {
                    Text("Original \(bytes(originalBytes))")
                    Spacer()
                    if targetSize {
                        Text("New ≤ \(bytes(Int(maxMB * 1_000_000)))")
                    } else if let estimate {
                        Text("New ≈ \(bytes(estimate)) (\(savings(estimate)))")
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .padding(12)
                .background(.white.opacity(0.35), in: .rect(cornerRadius: 12))
            }
        } controls: {
            if urls.count > 1 {
                Text("\(urls.count) photos").font(.caption.weight(.semibold))
            }
        }
        .task(id: "\(format)-\(quality)-\(scale)-\(targetSize)") {
            guard !targetSize else { return }
            estimate = nil
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let url = urls[0], target = target, quality = quality, scale = scale
            estimate = try? await offMain { try ImageTools.compressed(url, as: target, quality: quality, scale: scale).count }
        }
    }

    private func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    private func savings(_ estimate: Int) -> String {
        guard originalBytes > 0 else { return "" }
        let change = Double(estimate - originalBytes) / Double(originalBytes) * 100
        return String(format: "%+.0f%%", change)
    }

    private func apply() {
        let urls = urls, target = target, quality = quality, scale = scale
        let maxBytes = targetSize ? Int(max(maxMB, 0.01) * 1_000_000) : nil
        session.apply {
            var outputs: [URL] = []
            for url in urls {
                outputs.append(try await offMain {
                    let data = if let maxBytes {
                        try ImageTools.compressed(url, as: target, maxBytes: maxBytes)
                    } else {
                        try ImageTools.compressed(url, as: target, quality: quality, scale: scale)
                    }
                    return try ImageTools.saveCompressed(data, source: url, target: target)
                })
            }
            return outputs
        }
    }
}

// MARK: - QR codes

struct QRViewer: View {
    let url: URL
    @ObservedObject var session: EditorSession
    @State private var codes: [String]?

    var body: some View {
        EditorShell(title: "QR Codes", session: session, applyTitle: "Done", onApply: { session.close() }) {
            VStack(alignment: .leading, spacing: 10) {
                if let codes {
                    if codes.isEmpty {
                        Text("No QR code found in \(url.lastPathComponent).")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    ForEach(codes, id: \.self) { code in
                        HStack(spacing: 10) {
                            Text(code)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(3)
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(code, forType: .string)
                            }
                            .buttonStyle(GlassPillButtonStyle())
                            if let link = URL(string: code), link.scheme?.hasPrefix("http") == true {
                                Button("Open") { NSWorkspace.shared.open(link) }
                                    .buttonStyle(GlassPillButtonStyle(selected: true))
                            }
                        }
                        .padding(12)
                        .background(.white.opacity(0.35), in: .rect(cornerRadius: 12))
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .task {
            let url = url
            codes = (try? await offMain { try ImageTools.qrCodes(in: url) }) ?? []
        }
    }
}
