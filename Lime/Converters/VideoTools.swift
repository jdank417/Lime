//
//  VideoTools.swift
//  Lime
//

import AVFoundation
import CoreImage

/// The work behind the video tools.
nonisolated enum VideoTools {
    static func duration(_ url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    /// Display size, with the track's rotation applied.
    static func displaySize(_ url: URL) async throws -> CGSize {
        guard let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first else {
            throw LimeError.failed("No video in this file")
        }
        let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
        let rotated = size.applying(transform)
        return CGSize(width: abs(rotated.width), height: abs(rotated.height))
    }

    /// Evenly spaced frames for a timeline strip.
    static func thumbnails(_ url: URL, count: Int, height: CGFloat) async -> [CGImage] {
        let asset = AVURLAsset(url: url)
        guard let seconds = try? await asset.load(.duration).seconds, seconds > 0 else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: height * 3, height: height * 2)
        let tolerance = CMTime(seconds: seconds / Double(count * 2), preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let times = (0..<count).map { CMTime(seconds: seconds * (Double($0) + 0.5) / Double(count), preferredTimescale: 600) }
        var images: [CGImage] = []
        for await result in generator.images(for: times) {
            if let image = try? result.image { images.append(image) }
        }
        return images
    }

    static func frame(_ url: URL, at seconds: Double = 0) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    static func trim(_ url: URL, from start: Double, to end: Double, suffix: String = "trimmed") async throws -> URL {
        let (fileType, ext) = MediaConverter.container(for: url)
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                end: CMTime(seconds: end, preferredTimescale: 600))
        return try await MediaConverter.export(AVURLAsset(url: url), source: url, preset: AVAssetExportPresetHighestQuality,
                                               fileType: fileType, ext: ext, suffix: suffix) { $0.timeRange = range }
    }

    static func split(_ url: URL, at point: Double) async throws -> [URL] {
        let length = try await duration(url)
        let first = try await JobProgress.$span.withValue(0...0.5) {
            try await trim(url, from: 0, to: point, suffix: "part 1")
        }
        let second = try await JobProgress.$span.withValue(0.5...1) {
            try await trim(url, from: point, to: length, suffix: "part 2")
        }
        return [first, second]
    }

    /// Plays faster or slower; audio keeps its pitch.
    static func changeSpeed(_ url: URL, factor: Double, keepAudio: Bool) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let length = try await asset.load(.duration)
        let composition = AVMutableComposition()
        let range = CMTimeRange(start: .zero, duration: length)
        for track in try await asset.loadTracks(withMediaType: .video) {
            guard let copy = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try copy.insertTimeRange(try await track.load(.timeRange), of: track, at: .zero)
            copy.preferredTransform = try await track.load(.preferredTransform)
        }
        if keepAudio {
            for track in try await asset.loadTracks(withMediaType: .audio) {
                guard let copy = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                try copy.insertTimeRange(try await track.load(.timeRange), of: track, at: .zero)
            }
        }
        let scaled = CMTimeMultiplyByFloat64(length, multiplier: 1 / factor)
        for track in composition.tracks { track.scaleTimeRange(range, toDuration: scaled) }

        let (fileType, ext) = MediaConverter.container(for: url)
        let label = factor < 1 ? String(format: "%.2g× slower", 1 / factor) : String(format: "%.2g× faster", factor)
        return try await MediaConverter.export(composition, source: url, preset: AVAssetExportPresetHighestQuality,
                                               fileType: fileType, ext: ext, suffix: label) {
            $0.audioTimePitchAlgorithm = .spectral
        }
    }

    /// `rect` is normalized with a top-left origin over the displayed (upright) frame.
    static func crop(_ url: URL, to rect: CGRect) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let display = try await displaySize(url)
        let width = (rect.width * display.width / 2).rounded() * 2, height = (rect.height * display.height / 2).rounded() * 2
        let originX = rect.minX * display.width
        let originY = (1 - rect.maxY) * display.height   // Core Image is bottom-left origin
        let composition = try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            let source = request.sourceImage
            let crop = CGRect(x: source.extent.minX + originX, y: source.extent.minY + originY, width: width, height: height)
            let output = source.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            request.finish(with: output, context: nil)
        }
        composition.renderSize = CGSize(width: width, height: height)
        let (fileType, ext) = MediaConverter.container(for: url)
        return try await MediaConverter.export(asset, source: url, preset: AVAssetExportPresetHighestQuality,
                                               fileType: fileType, ext: ext, suffix: "cropped") {
            $0.videoComposition = composition
        }
    }

    struct CompressPreset: Hashable, Sendable {
        let label: String
        let preset: String
        let hevcPreset: String?

        static let all: [CompressPreset] = [
            .init(label: "Same size", preset: AVAssetExportPresetHighestQuality, hevcPreset: AVAssetExportPresetHEVCHighestQuality),
            .init(label: "1080p", preset: AVAssetExportPreset1920x1080, hevcPreset: AVAssetExportPresetHEVC1920x1080),
            .init(label: "720p", preset: AVAssetExportPreset1280x720, hevcPreset: nil),
            .init(label: "540p", preset: AVAssetExportPreset960x540, hevcPreset: nil),
            .init(label: "480p", preset: AVAssetExportPreset640x480, hevcPreset: nil),
        ]

        func name(hevc: Bool) -> String { hevc && hevcPreset != nil ? hevcPreset! : preset }
    }

    static func estimatedSize(_ url: URL, preset: String) async -> Int64? {
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: preset) else { return nil }
        session.outputFileType = .mp4
        return try? await session.estimatedOutputFileLengthInBytes
    }

    static func compress(_ url: URL, preset: String) async throws -> URL {
        try await MediaConverter.export(AVURLAsset(url: url), source: url, preset: preset, fileType: .mp4, ext: "mp4",
                                        suffix: "compressed") { $0.shouldOptimizeForNetworkUse = true }
    }

    /// Plays the videos one after another in a single file.
    static func join(_ urls: [URL]) async throws -> URL {
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw LimeError.failed("Couldn't join the videos") }
        var cursor = CMTime.zero
        for (index, url) in urls.enumerated() {
            let asset = AVURLAsset(url: url)
            let length = try await asset.load(.duration)
            let range = CMTimeRange(start: .zero, duration: length)
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                try video.insertTimeRange(range, of: track, at: cursor)
                if index == 0 { video.preferredTransform = try await track.load(.preferredTransform) }
            }
            if let track = try await asset.loadTracks(withMediaType: .audio).first {
                try audio.insertTimeRange(range, of: track, at: cursor)
            }
            cursor = cursor + length
        }
        if audio.segments.isEmpty { composition.removeTrack(audio) }
        return try await MediaConverter.export(composition, source: urls[0], preset: AVAssetExportPresetHighestQuality,
                                               fileType: .mp4, ext: "mp4", base: "Joined")
    }
}
