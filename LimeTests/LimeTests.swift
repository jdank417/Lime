//
//  LimeTests.swift
//  LimeTests
//
//  Created by Jason Dank on 10/25/26.
//

import AVFoundation
import AppKit
import Foundation
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import Lime

/// Each test works in its own temporary folder, with fixtures generated on the fly.
@MainActor
struct LimeTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("LimeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: Wheel

    @Test func wheelHitTesting() {
        let c = WheelGeometry.size / 2
        let mid = (WheelGeometry.inner + WheelGeometry.outer) / 2
        #expect(WheelGeometry.index(at: CGPoint(x: c, y: c), count: 4) == nil)
        #expect(WheelGeometry.index(at: CGPoint(x: c, y: c - mid), count: 4) == 0) // top
        #expect(WheelGeometry.index(at: CGPoint(x: c + mid, y: c), count: 4) == 1) // right
        #expect(WheelGeometry.index(at: CGPoint(x: c, y: c + mid), count: 4) == 2) // bottom
        #expect(WheelGeometry.index(at: CGPoint(x: c - mid, y: c), count: 4) == 3) // left
        #expect(WheelGeometry.index(at: CGPoint(x: c - 5, y: c - mid), count: 4) == 0) // just left of top
        #expect(WheelGeometry.index(at: CGPoint(x: c, y: c - mid), count: 0) == nil)
    }

    @Test func outputNamesNeverOverwrite() throws {
        let source = dir.appendingPathComponent("photo.heic")
        #expect(Output.url(for: source, ext: "png").lastPathComponent == "photo.png")
        try Data().write(to: dir.appendingPathComponent("photo.png"))
        #expect(Output.url(for: source, ext: "png").lastPathComponent == "photo 2.png")
        #expect(Output.url(for: source, ext: "jpg", suffix: "rotated").lastPathComponent == "photo (rotated).jpg")
        #expect(Output.baseName(of: dir.appendingPathComponent("backup.tar.gz")) == "backup")
    }

    @Test func catalogMatchesFileKinds() throws {
        let png = try makePNG()
        let labels = ActionCatalog.actions(for: [png], mode: .convert).map(\.label)
        #expect(labels.contains("JPG") && !labels.contains("PNG"))
        #expect(ActionCatalog.actions(for: [png, try makePNG("b")], mode: .convert).first?.label == "1 PDF")
        #expect(ActionCatalog.actions(for: [png, try makeText()], mode: .convert).map(\.label) == ["ZIP", "TAR.GZ"])
        #expect(ActionCatalog.actions(for: [dir], mode: .convert).map(\.label) == ["ZIP", "TAR.GZ", "DMG"])
    }

    // MARK: Images

    @Test func imageConversions() async throws {
        let png = try makePNG()
        for action in ActionCatalog.actions(for: [png], mode: .convert) {
            let outputs = try await action.run([png])
            #expect(outputs.count == 1)
            #expect(fileSize(outputs[0]) > 0, "\(action.label) produced nothing")
            if !["PDF", "SVG", "DOCX"].contains(action.label) {
                #expect(CGImageSourceCreateWithURL(outputs[0] as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }?.width == 64,
                        "\(action.label) isn't a readable 64px image")
            }
        }
    }

    @Test func imageTools() async throws {
        let png = try makePNG(width: 64, height: 32)
        let half = try ImageConverter.edit(png, .halfSize)
        #expect(pixelSize(half) == CGSize(width: 32, height: 16))
        let rotated = try ImageConverter.edit(png, .rotate)
        #expect(pixelSize(rotated) == CGSize(width: 32, height: 64))
        #expect(rotated.lastPathComponent == "image (rotated).png")
        #expect(try ImageConverter.edit(png, .compress).pathExtension == "jpg")
        for action in ActionCatalog.actions(for: [png], mode: .tools) where !action.interactive {
            #expect(try await action.run([png]).allSatisfy { fileSize($0) > 0 }, "\(action.label) failed")
        }
    }

    // MARK: PDF

    @Test func pdfRoundTrip() async throws {
        let a = try ImageConverter.convert(try makePNG("a"), to: ImageConverter.targets.first { $0.ext == "pdf" }!)
        let b = try ImageConverter.convert(try makePNG("b"), to: ImageConverter.targets.first { $0.ext == "pdf" }!)
        let merged = try PDFConverter.merge([a, b])
        #expect(PDFDocument(url: merged)?.pageCount == 2)

        let images = try PDFConverter.toImages(merged, target: ImageConverter.png)
        #expect(try FileManager.default.contentsOfDirectory(atPath: images.path).count == 2)
        let pages = try PDFConverter.split(merged)
        #expect(try FileManager.default.contentsOfDirectory(atPath: pages.path).count == 2)
        #expect(PDFDocument(url: try PDFConverter.rotate(a))?.page(at: 0)?.rotation == 90)
        #expect(fileSize(try PDFConverter.compress(merged)) > 0)

        let single = try PDFConverter.toImages(a, target: ImageConverter.jpeg)
        #expect(single.lastPathComponent == "a.jpg")
    }

    @Test func pdfFromTextHasText() async throws {
        let text = try makeText()
        let pdf = try DocumentConverter.convert(text, to: DocumentConverter.targets.first { $0.ext == "pdf" }!)
        let document = try #require(PDFDocument(url: pdf))
        #expect(document.pageCount >= 2, "long text should paginate")
        #expect(document.string?.contains("Lime line 1") == true)

        let extracted = try PDFConverter.toText(pdf)
        #expect(try String(contentsOf: extracted, encoding: .utf8).contains("Lime line 1"))
    }

    // MARK: Documents

    @Test func documentConversions() async throws {
        let text = try makeText()
        for action in ActionCatalog.actions(for: [text], mode: .convert) {
            let output = try await action.run([text])[0]
            #expect(fileSize(output) > 0, "\(action.label) produced nothing")
            if action.label != "PDF" {
                let back = try DocumentConverter.load(output)
                #expect(back.string.contains("Lime line 1"), "\(action.label) lost the text")
            }
        }
    }

    @Test func markdownKeepsBold() throws {
        let md = dir.appendingPathComponent("notes.md")
        try "Hello **bold** world".write(to: md, atomically: true, encoding: .utf8)
        let rtf = try DocumentConverter.convert(md, to: DocumentConverter.targets.first { $0.ext == "rtf" }!)
        let back = try DocumentConverter.load(rtf)
        #expect(back.string == "Hello bold world")
        let font = back.attribute(.font, at: 7, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    // MARK: Audio & video

    @Test func audioConversions() async throws {
        let wav = try makeWAV()
        for action in ActionCatalog.actions(for: [wav], mode: .convert) + ActionCatalog.actions(for: [wav], mode: .tools) where !action.interactive {
            let output = try await action.run([wav])[0]
            if action.label == "ZIP" { continue }
            let file = try AVAudioFile(forReading: output)
            #expect(abs(Double(file.length) / file.fileFormat.sampleRate - 1) < 0.1, "\(action.label) has the wrong length")
        }
    }

    @Test func videoConversions() async throws {
        let mov = try await makeMovie()
        for action in ActionCatalog.actions(for: [mov], mode: .convert) + ActionCatalog.actions(for: [mov], mode: .tools) where !action.interactive {
            let output = try await action.run([mov])[0]
            #expect(fileSize(output) > 0, "\(action.label) produced nothing")
        }
        let gif = try await MediaConverter.gif(mov)
        #expect(CGImageSourceCreateWithURL(gif as CFURL, nil).map(CGImageSourceGetCount) ?? 0 > 5)
    }

    // MARK: Archives

    @Test func archiveRoundTrip() async throws {
        let folder = dir.appendingPathComponent("Stuff", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "hi".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let zip = try await ArchiveTool.zip([folder])
        #expect(zip.lastPathComponent == "Stuff.zip")
        try FileManager.default.removeItem(at: folder)

        // The zip holds one folder, so extracting gives back "Stuff" rather than "Stuff/Stuff".
        let extracted = try await ArchiveTool.extract(zip)
        #expect(extracted.lastPathComponent == "Stuff")
        #expect(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("a.txt").path))

        let tgz = try await ArchiveTool.repack(zip, as: "tar.gz")
        #expect(tgz.lastPathComponent == "Stuff.tar.gz")
        let back = try await ArchiveTool.repack(tgz, as: "zip")
        #expect(back.lastPathComponent == "Stuff 2.zip")

        let many = try await ArchiveTool.zip([try makePNG("x"), try makePNG("y")])
        #expect(many.lastPathComponent == "Archive.zip")
        #expect(fileSize(try await ArchiveTool.diskImage(extracted)) > 0)
    }

    // MARK: Fixtures

    func makePNG(_ name: String = "image", width: Int = 64, height: Int = 64) throws -> URL {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.8, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        let url = dir.appendingPathComponent("\(name).png")
        try ImageConverter.write(ctx.makeImage()!, to: url, type: .png)
        return url
    }

    func makeText() throws -> URL {
        let url = dir.appendingPathComponent("notes.txt")
        try (1...120).map { "Lime line \($0)" }.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// One second of a 440 Hz tone.
    func makeWAV() throws -> URL {
        let url = dir.appendingPathComponent("tone.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        buffer.frameLength = 44_100
        for channel in 0..<2 {
            for i in 0..<44_100 { buffer.floatChannelData![channel][i] = Float(sin(Double(i) * 2 * .pi * 440 / 44_100) * 0.3) }
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            ])
            try file.write(from: buffer)
        }
        return url
    }

    /// Two seconds of 320×240 H.264 with an AAC soundtrack.
    func makeMovie() async throws -> URL {
        let url = dir.appendingPathComponent("clip.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320,
            kCVPixelBufferHeightKey as String: 240,
        ])
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
        ])
        writer.add(video)
        writer.add(audio)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let rate = 44_100
        let samples = [Int16](repeating: 0, count: rate * 2)
        var block: CMBlockBuffer?
        let bytes = samples.count * 2
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                                           customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block)
        samples.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: bytes) }
        var asbd = AudioStreamBasicDescription(mSampleRate: Float64(rate), mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
                                               mBitsPerChannel: 16, mReserved: 0)
        var formatDescription: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &formatDescription)
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block!, formatDescription: formatDescription!,
                                                             sampleCount: samples.count, presentationTimeStamp: .zero,
                                                             packetDescriptions: nil, sampleBufferOut: &sample)
        try await waitUntilReady(audio, writer)
        audio.append(sample!)
        audio.markAsFinished()

        for frame in 0..<60 {
            try await waitUntilReady(video, writer)
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
            let buffer = pixelBuffer!
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(frame * 4), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        video.markAsFinished()

        await writer.finishWriting()
        try #require(writer.status == .completed, "\(writer.error.map(String.init(describing:)) ?? "")")
        return url
    }

    func waitUntilReady(_ input: AVAssetWriterInput, _ writer: AVAssetWriter) async throws {
        while !input.isReadyForMoreMediaData {
            try #require(writer.status == .writing, "\(writer.error.map(String.init(describing:)) ?? "")")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func fileSize(_ url: URL) -> Int {
        if FileKind.of(url) == .folder { return 1 }
        return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    func pixelSize(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return CGSize(width: image.width, height: image.height)
    }
}
