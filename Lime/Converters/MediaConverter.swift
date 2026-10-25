//
//  MediaConverter.swift
//  Lime
//

import AVFoundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum MediaConverter {
    // MARK: Video

    struct VideoTarget: Sendable {
        let label: String
        let ext: String
        let preset: String
        let fileType: AVFileType
        var suffix: String? = nil
    }

    static let videoTargets: [VideoTarget] = [
        .init(label: "MP4", ext: "mp4", preset: AVAssetExportPresetHighestQuality, fileType: .mp4),
        .init(label: "MOV", ext: "mov", preset: AVAssetExportPresetHighestQuality, fileType: .mov),
        .init(label: "M4V", ext: "m4v", preset: AVAssetExportPresetHighestQuality, fileType: .m4v),
        .init(label: "HEVC", ext: "mp4", preset: AVAssetExportPresetHEVCHighestQuality, fileType: .mp4, suffix: "HEVC"),
    ]

    static let resizeTargets: [VideoTarget] = [
        .init(label: "1080p", ext: "mp4", preset: AVAssetExportPreset1920x1080, fileType: .mp4, suffix: "1080p"),
        .init(label: "720p", ext: "mp4", preset: AVAssetExportPreset1280x720, fileType: .mp4, suffix: "720p"),
        .init(label: "480p", ext: "mp4", preset: AVAssetExportPreset640x480, fileType: .mp4, suffix: "480p"),
    ]

    static func convert(_ url: URL, to target: VideoTarget) async throws -> URL {
        try await export(AVURLAsset(url: url), source: url, preset: target.preset,
                         fileType: target.fileType, ext: target.ext, suffix: target.suffix)
    }

    static func extractAudio(_ url: URL) async throws -> URL {
        try await export(AVURLAsset(url: url), source: url, preset: AVAssetExportPresetAppleM4A, fileType: .m4a, ext: "m4a")
    }

    static func removeAudio(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let composition = AVMutableComposition()
        for track in try await asset.loadTracks(withMediaType: .video) {
            guard let copy = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try copy.insertTimeRange(try await track.load(.timeRange), of: track, at: .zero)
            copy.preferredTransform = try await track.load(.preferredTransform)
        }
        let ext = ["mp4", "m4v"].contains(normalizedExtension(of: url)) ? normalizedExtension(of: url) : "mov"
        let fileType: AVFileType = ext == "mp4" ? .mp4 : ext == "m4v" ? .m4v : .mov
        return try await export(composition, source: url, preset: AVAssetExportPresetPassthrough,
                                fileType: fileType, ext: ext, suffix: "no audio")
    }

    static func snapshot(_ url: URL) async throws -> URL {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        let (image, _) = try await generator.image(at: .zero)
        let out = Output.url(for: url, ext: "png", suffix: "frame")
        try ImageConverter.write(image, to: out, type: .png)
        return out
    }

    /// Animated GIF of the first 15 seconds at 10 fps, at most 480 px wide.
    static func gif(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let seconds = min(try await asset.load(.duration).seconds, 15)
        let fps = 10.0
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        let tolerance = CMTime(value: 1, timescale: 20)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let times = stride(from: 0.0, to: max(seconds, 0.1), by: 1 / fps).map { CMTime(seconds: $0, preferredTimescale: 600) }
        var frames: [CGImage] = []
        for await result in generator.images(for: times) {
            if let image = try? result.image { frames.append(image) }
        }
        guard !frames.isEmpty else { throw LimeError.failed("Couldn't read frames from the video") }

        let out = Output.url(for: url, ext: "gif")
        guard let destination = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw LimeError.failed("Couldn't create the GIF")
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
        for frame in frames { CGImageDestinationAddImage(destination, frame, frameProperties) }
        guard CGImageDestinationFinalize(destination) else { throw LimeError.failed("Couldn't save the GIF") }
        return out
    }

    private static func export(_ asset: AVAsset, source: URL, preset: String, fileType: AVFileType,
                               ext: String, suffix: String? = nil) async throws -> URL {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw LimeError.failed("This file can't be exported that way")
        }
        let out = Output.url(for: source, ext: ext, suffix: suffix)
        try await session.export(to: out, as: fileType)
        return out
    }

    // MARK: Audio

    struct AudioTarget: Sendable {
        let label: String
        let ext: String
        var suffix: String? = nil
        let settings: @Sendable (AVAudioFormat) -> [String: Any]
    }

    static let audioTargets: [AudioTarget] = [
        .init(label: "M4A", ext: "m4a") { aac($0, bitRate: nil) },
        .init(label: "WAV", ext: "wav") { pcm($0, bigEndian: false) },
        .init(label: "AIFF", ext: "aiff") { pcm($0, bigEndian: true) },
        .init(label: "FLAC", ext: "flac") { lossless($0, format: kAudioFormatFLAC) },
        .init(label: "ALAC", ext: "m4a", suffix: "lossless") { lossless($0, format: kAudioFormatAppleLossless) },
    ]

    static let compressAudio = AudioTarget(label: "Compress", ext: "m4a", suffix: "compressed") {
        aac($0, bitRate: $0.channelCount == 1 ? 64_000 : 96_000)
    }

    static func convert(_ url: URL, to target: AudioTarget) throws -> URL {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        let out = Output.url(for: url, ext: target.ext, suffix: target.suffix)
        do {
            let output = try AVAudioFile(forWriting: out, settings: target.settings(input.fileFormat),
                                         commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65_536) else {
                throw LimeError.failed("Couldn't read the audio")
            }
            while input.framePosition < input.length {
                try input.read(into: buffer)
                if buffer.frameLength == 0 { break }
                try output.write(from: buffer)
            }
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
        return out
    }

    private static func aac(_ format: AVAudioFormat, bitRate: Int?) -> [String: Any] {
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
        ]
        if let bitRate {
            settings[AVEncoderBitRateKey] = bitRate
        } else {
            settings[AVEncoderAudioQualityKey] = AVAudioQuality.high.rawValue
        }
        return settings
    }

    private static func pcm(_ format: AVAudioFormat, bigEndian: Bool) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: bigEndian,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    private static func lossless(_ format: AVAudioFormat, format id: AudioFormatID) -> [String: Any] {
        [
            AVFormatIDKey: id,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitDepthHintKey: 16,
        ]
    }
}
