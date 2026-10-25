//
//  ToolTests.swift
//  LimeTests
//

import AVFoundation
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import PDFKit
import Testing
@testable import Lime

/// The processing behind each tool window, driven directly with generated files.
extension LimeTests {
    // MARK: Photos

    @Test func photoEdits() throws {
        let png = try makePNG(width: 80, height: 40)

        var adjustments = ImageTools.Adjustments()
        adjustments.exposure = 1
        adjustments.highlights = 50
        adjustments.warmth = 30
        let edited = try ImageTools.applyAdjustments(png, adjustments)
        #expect(pixelSize(edited) == CGSize(width: 80, height: 40))

        let cropped = try ImageTools.applyCrop(png, rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        #expect(pixelSize(cropped) == CGSize(width: 40, height: 20))

        let redacted = try ImageTools.applyRedaction(png, rects: [CGRect(x: 0, y: 0, width: 0.5, height: 1)], style: .black)
        let pixel = try #require(ImageConverter.render(ImageConverter.load(redacted)).dataProvider?.data as Data?)
        #expect(pixel[0] < 10 && pixel[1] < 10, "left half should be black")
        for style in ImageTools.RedactStyle.allCases {
            #expect(fileSize(try ImageTools.applyRedaction(png, rects: [CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)], style: style)) > 0)
        }

        let marks = [
            ImageTools.Mark(kind: .arrow, points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.9)], color: RGBA(1, 0, 0), width: 0.05),
            ImageTools.Mark(kind: .pen, points: [CGPoint(x: 0.2, y: 0.8), CGPoint(x: 0.5, y: 0.5)], color: RGBA(0, 0, 1), width: 0.03),
            ImageTools.Mark(kind: .text, points: [CGPoint(x: 0.1, y: 0.5)], color: RGBA(0, 0, 0), width: 0.02, text: "Hi"),
        ]
        #expect(pixelSize(try ImageTools.applyAnnotations(png, marks: marks)) == CGSize(width: 80, height: 40))

        let backed = try ImageTools.applyBackground(png, .init(colors: [RGBA(0, 0, 1), RGBA(0, 1, 0)], padding: 0.25))
        #expect(pixelSize(backed) == CGSize(width: 120, height: 80))
        #expect(backed.pathExtension == "png")
    }

    @Test func compressToTargetSize() throws {
        // Noise compresses badly, so it takes real work to get under the limit.
        let noise = CIFilter.randomGenerator().outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 900, height: 900))
        let url = dir.appendingPathComponent("noise.png")
        try ImageConverter.write(ImageConverter.render(noise), to: url, type: .png)

        let data = try ImageTools.compressed(url, as: ImageConverter.jpeg, maxBytes: 60_000)
        #expect(data.count <= 60_000)
        let loose = try ImageTools.compressed(url, as: ImageConverter.jpeg, quality: 0.9, scale: 1)
        let tight = try ImageTools.compressed(url, as: ImageConverter.jpeg, quality: 0.3, scale: 0.5)
        #expect(tight.count < loose.count)
    }

    @Test func readsQRCodes() throws {
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data("https://example.com/lime".utf8)
        let code = generator.outputImage!.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let padded = code.composited(over: CIImage(color: .white).cropped(to: code.extent.insetBy(dx: -40, dy: -40)))
        let url = dir.appendingPathComponent("qr.png")
        try ImageConverter.write(ImageConverter.render(padded), to: url, type: .png)
        #expect(try ImageTools.qrCodes(in: url) == ["https://example.com/lime"])
        #expect(try ImageTools.qrCodes(in: try makePNG()) == [])
    }

    @Test func extraImageFormats() async throws {
        let png = try makePNG()
        let svg = try String(contentsOf: try ImageTools.svg(png), encoding: .utf8)
        #expect(svg.contains("<svg") && svg.contains("data:image/png;base64"))

        let docx = try await WordImage.document(for: png)
        let bytes = try Data(contentsOf: docx)
        #expect(bytes.range(of: Data("word/media/image1.png".utf8)) != nil, "the picture should be inside the .docx")
        // AppKit can open it back up, which means the package is well-formed.
        #expect(try NSAttributedString(url: docx, options: [:], documentAttributes: nil).length > 0)

        let collage = try ImageTools.collage([png, try makePNG("b"), try makePNG("c")])
        #expect(pixelSize(collage) == CGSize(width: 2 * 924 + 24, height: 2 * 924 + 24))
        #expect(ImageConverter.targets.contains { $0.ext == "avif" })
    }

    // MARK: Subtitles

    @Test func subtitlesRoundTrip() throws {
        let srt = dir.appendingPathComponent("movie.srt")
        try "1\n00:00:01,500 --> 00:00:03,000\nHello there\n\n2\n00:01:02,000 --> 00:01:04,250\nTwo\nlines\n"
            .write(to: srt, atomically: true, encoding: .utf8)
        let vtt = try SubtitleConverter.convert(srt, to: "vtt")
        let vttText = try String(contentsOf: vtt, encoding: .utf8)
        #expect(vttText.hasPrefix("WEBVTT"))
        #expect(vttText.contains("00:00:01.500 --> 00:00:03.000"))

        let back = try SubtitleConverter.convert(vtt, to: "srt")
        #expect(SubtitleConverter.parse(try String(contentsOf: back, encoding: .utf8)) ==
                SubtitleConverter.parse(try String(contentsOf: srt, encoding: .utf8)))
        let txt = try String(contentsOf: try SubtitleConverter.convert(srt, to: "txt"), encoding: .utf8)
        #expect(txt == "Hello there\nTwo\nlines")
        #expect(FileKind.of(srt) == .subtitle)
    }

    // MARK: Audio

    @Test func audioTools() throws {
        let wav = try makeWAV()
        let trimmed = try AVAudioFile(forReading: try AudioTools.trim(wav, from: 0.25, to: 0.75))
        #expect(abs(Double(trimmed.length) / trimmed.fileFormat.sampleRate - 0.5) < 0.02)

        let normalized = try AudioTools.normalize(wav)
        let peak = try AudioTools.waveform(normalized, bins: 1).peaks[0]
        #expect(abs(peak - 0.891) < 0.02, "peak was \(peak)")

        let mono = try AVAudioFile(forReading: try AudioTools.channels(wav, mono: true, left: 1, right: 1))
        #expect(mono.fileFormat.channelCount == 1)
        let quiet = try AudioTools.channels(wav, mono: false, left: 0, right: 1)
        #expect(try AVAudioFile(forReading: quiet).fileFormat.channelCount == 2)

        let wave = try AudioTools.waveform(wav, bins: 100)
        #expect(wave.peaks.count == 100 && abs(wave.duration - 1) < 0.01)
        #expect(AudioTools.soundBounds([0, 0, 0.5, 0.5, 0]) == 0.4...0.8)
    }

    // MARK: Video

    @Test func videoTools() async throws {
        let mov = try await makeMovie()

        let trimmed = try await VideoTools.trim(mov, from: 0.5, to: 1.5)
        #expect(abs(try await VideoTools.duration(trimmed) - 1) < 0.15)

        let parts = try await VideoTools.split(mov, at: 0.8)
        #expect(parts.count == 2)
        #expect(abs(try await VideoTools.duration(parts[0]) - 0.8) < 0.15)

        let fast = try await VideoTools.changeSpeed(mov, factor: 2, keepAudio: true)
        #expect(abs(try await VideoTools.duration(fast) - 1) < 0.15)

        let square = try await VideoTools.crop(mov, to: CropOverlay.fullRect(ratio: 1, pixelSize: CGSize(width: 320, height: 240)))
        #expect(try await VideoTools.displaySize(square) == CGSize(width: 240, height: 240))

        let joined = try await VideoTools.join([mov, mov])
        #expect(abs(try await VideoTools.duration(joined) - 4) < 0.2)

        #expect(await VideoTools.estimatedSize(mov, preset: VideoTools.CompressPreset.all[4].preset) != nil)
        #expect(fileSize(try await VideoTools.compress(mov, preset: VideoTools.CompressPreset.all[4].preset)) > 0)
        #expect(await VideoTools.thumbnails(mov, count: 4, height: 40).count == 4)
    }

    // MARK: Metadata & PDF

    @Test func metadataEdits() async throws {
        let jpg = try ImageConverter.convert(try makePNG(), to: ImageConverter.jpeg)
        let saved = try await MetadataTool.save(jpg, fields: ["title": "Lime test", "artist": "Jason"], removeLocation: true)
        let info = try await MetadataTool.read(saved)
        #expect(info.fields.first { $0.key == "title" }?.value == "Lime test")
        #expect(info.fields.first { $0.key == "artist" }?.value == "Jason")

        let pdf = try ImageConverter.convert(try makePNG("p"), to: ImageConverter.targets.first { $0.ext == "pdf" }!)
        let pdfInfo = try await MetadataTool.read(try await MetadataTool.save(pdf, fields: ["author": "Lime"], removeLocation: false))
        #expect(pdfInfo.fields.first { $0.key == "author" }?.value == "Lime")

        let mov = try await makeMovie()
        let tagged = try await MetadataTool.save(mov, fields: ["title": "Clip"], removeLocation: false)
        #expect(try await MetadataTool.read(tagged).fields.first { $0.key == "title" }?.value == "Clip")
        let stripped = try await MetadataTool.strip(tagged)
        #expect(try await MetadataTool.read(stripped).fields.first { $0.key == "title" }?.value == "")
    }

    @Test func reorganizePDF() throws {
        let pdf = { (name: String) in try ImageConverter.convert(try self.makePNG(name), to: ImageConverter.targets.first { $0.ext == "pdf" }!) }
        let merged = try PDFConverter.merge([try pdf("a"), try pdf("b"), try pdf("c")])
        let result = try PDFConverter.reorganize(merged, pages: [.init(index: 2, rotation: 90), .init(index: 0, rotation: 0)])
        let document = try #require(PDFDocument(url: result))
        #expect(document.pageCount == 2)
        #expect(document.page(at: 0)?.rotation == 90)
        #expect(try PDFConverter.thumbnails(merged, size: 50).count == 3)
    }

    // MARK: Settings

    @Test func saveLocationSetting() throws {
        // The test host shares Lime's real settings, so put them back afterwards.
        let defaults = UserDefaults.standard
        let saved = (defaults.object(forKey: Prefs.Key.saveLocation), defaults.object(forKey: Prefs.Key.customFolder))
        defer {
            defaults.set(saved.0, forKey: Prefs.Key.saveLocation)
            defaults.set(saved.1, forKey: Prefs.Key.customFolder)
        }
        let source = try makePNG()
        let folder = dir.appendingPathComponent("Out", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        defaults.set(Prefs.SaveLocation.folder.rawValue, forKey: Prefs.Key.saveLocation)
        Prefs.customFolder = folder
        let converted = try ImageConverter.convert(source, to: ImageConverter.jpeg)
        #expect(converted.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)

        defaults.set(Prefs.SaveLocation.beside.rawValue, forKey: Prefs.Key.saveLocation)
        #expect(Output.directory(for: source) == source.deletingLastPathComponent())

        // A folder that's gone falls back to beside the original.
        defaults.set(Prefs.SaveLocation.folder.rawValue, forKey: Prefs.Key.saveLocation)
        Prefs.customFolder = dir.appendingPathComponent("Missing", isDirectory: true)
        #expect(Output.directory(for: source) == source.deletingLastPathComponent())
    }

    // MARK: Catalog

    @Test func toolsCatalog() throws {
        let png = try makePNG()
        let tools = ActionCatalog.actions(for: [png], mode: .tools).map(\.label)
        #expect(tools == ["Compress", "Metadata", "Edit", "Annotate", "Add BG", "Crop", "Redact", "Rotate", "QR Code"])
        let convert = ActionCatalog.actions(for: [png], mode: .convert).map(\.label)
        #expect(convert.contains("AVIF") && convert.contains("SVG") && convert.contains("DOCX") && !convert.contains("PNG"))
        #expect(ActionCatalog.actions(for: [try makeWAV()], mode: .tools).map(\.label) == ["Compress", "Trim", "Normalize", "Channels", "Metadata"])
    }
}
