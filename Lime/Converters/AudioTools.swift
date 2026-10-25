//
//  AudioTools.swift
//  Lime
//

import AVFoundation

/// The work behind the audio tools. All of them stream, so long recordings don't fill memory.
nonisolated enum AudioTools {
    private static let chunk: AVAudioFrameCount = 65_536

    /// Loudest sample per bin (0…1) for drawing a waveform.
    static func waveform(_ url: URL, bins: Int) throws -> (peaks: [Float], duration: Double) {
        let file = try AVAudioFile(forReading: url)
        let total = max(file.length, 1)
        var peaks = [Float](repeating: 0, count: bins)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else {
            throw LimeError.unreadable(url.lastPathComponent)
        }
        var position: AVAudioFramePosition = 0
        while file.framePosition < file.length {
            try file.read(into: buffer)
            let frames = Int(buffer.frameLength)
            if frames == 0 { break }
            for channel in 0..<Int(buffer.format.channelCount) {
                guard let samples = buffer.floatChannelData?[channel] else { continue }
                for i in 0..<frames {
                    let bin = min(Int((position + AVAudioFramePosition(i)) * AVAudioFramePosition(bins) / total), bins - 1)
                    peaks[bin] = max(peaks[bin], abs(samples[i]))
                }
            }
            position += AVAudioFramePosition(frames)
        }
        return (peaks, Double(file.length) / file.fileFormat.sampleRate)
    }

    /// Where the sound starts and stops (as fractions), ignoring near-silence at either end.
    static func soundBounds(_ peaks: [Float], threshold: Float = 0.01) -> ClosedRange<Double> {
        guard let first = peaks.firstIndex(where: { $0 > threshold }),
              let last = peaks.lastIndex(where: { $0 > threshold }) else { return 0...1 }
        let count = Double(peaks.count)
        return Double(first) / count...min(Double(last + 1) / count, 1)
    }

    static func trim(_ url: URL, from start: Double, to end: Double) throws -> URL {
        let rate = try AVAudioFile(forReading: url).fileFormat.sampleRate
        let range = AVAudioFramePosition(start * rate)..<AVAudioFramePosition(end * rate)
        return try rewrite(url, suffix: "trimmed", range: range) { input, output in
            copy(input, into: output, gains: [1, 1])
        }
    }

    /// Raises (or lowers) the volume so the loudest moment sits just under clipping.
    static func normalize(_ url: URL) throws -> URL {
        let peak = try waveform(url, bins: 1).peaks.first ?? 0
        guard peak > 0 else { throw LimeError.failed("This file is silent") }
        let gain = Float(0.891) / peak   // -1 dBFS
        return try rewrite(url, suffix: "normalized") { input, output in
            copy(input, into: output, gains: [gain, gain])
        }
    }

    /// Mono or stereo output, with a level for each side.
    static func channels(_ url: URL, mono: Bool, left: Float, right: Float) throws -> URL {
        try rewrite(url, suffix: mono ? "mono" : "stereo", outputChannels: mono ? 1 : 2) { input, output in
            let frames = Int(input.frameLength)
            guard let source = input.floatChannelData, let destination = output.floatChannelData else { return }
            let l = source[0]
            let r = input.format.channelCount > 1 ? source[1] : source[0]
            if mono {
                for i in 0..<frames { destination[0][i] = (l[i] * left + r[i] * right) / 2 }
            } else {
                for i in 0..<frames {
                    destination[0][i] = l[i] * left
                    destination[1][i] = r[i] * right
                }
            }
        }
    }

    /// Same format as the source when Lime can write it; otherwise AAC in M4A.
    static func outputTarget(for url: URL) -> MediaConverter.AudioTarget {
        let label = switch normalizedExtension(of: url) {
        case "wav": "WAV"
        case "aiff": "AIFF"
        case "flac": "FLAC"
        default: "M4A"
        }
        return MediaConverter.audioTargets.first { $0.label == label } ?? MediaConverter.audioTargets[0]
    }

    private static func copy(_ input: AVAudioPCMBuffer, into output: AVAudioPCMBuffer, gains: [Float]) {
        guard let source = input.floatChannelData, let destination = output.floatChannelData else { return }
        for channel in 0..<Int(output.format.channelCount) {
            let from = source[min(channel, Int(input.format.channelCount) - 1)]
            let gain = gains[min(channel, gains.count - 1)]
            for i in 0..<Int(input.frameLength) {
                destination[channel][i] = min(max(from[i] * gain, -1), 1)
            }
        }
    }

    /// Streams `url` through `transform` into a new file next to it.
    private static func rewrite(_ url: URL, suffix: String, outputChannels: AVAudioChannelCount? = nil,
                                range: Range<AVAudioFramePosition>? = nil,
                                transform: (AVAudioPCMBuffer, AVAudioPCMBuffer) -> Void) throws -> URL {
        let input = try AVAudioFile(forReading: url)
        let inFormat = input.processingFormat
        guard let outFormat = AVAudioFormat(standardFormatWithSampleRate: inFormat.sampleRate,
                                            channels: outputChannels ?? inFormat.channelCount),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: chunk),
              let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: chunk)
        else { throw LimeError.unreadable(url.lastPathComponent) }

        let target = outputTarget(for: url)
        let out = Output.url(for: url, ext: target.ext, suffix: suffix)
        let range = range ?? 0..<input.length
        let end = min(range.upperBound, input.length)
        do {
            let output = try AVAudioFile(forWriting: out, settings: target.settings(outFormat),
                                         commonFormat: .pcmFormatFloat32, interleaved: false)
            input.framePosition = max(range.lowerBound, 0)
            while input.framePosition < end {
                let wanted = AVAudioFrameCount(min(AVAudioFramePosition(chunk), end - input.framePosition))
                try input.read(into: inBuffer, frameCount: wanted)
                if inBuffer.frameLength == 0 { break }
                outBuffer.frameLength = inBuffer.frameLength
                transform(inBuffer, outBuffer)
                try output.write(from: outBuffer)
                JobProgress.report(Double(input.framePosition - range.lowerBound) / Double(max(end - range.lowerBound, 1)))
            }
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
        return out
    }
}
