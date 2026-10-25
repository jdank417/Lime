//
//  MediaEditors.swift
//  Lime
//

import AVFoundation
import AVKit
import SwiftUI

// MARK: - Timeline

/// A strip (thumbnails or waveform) with lime handles for a start and end, or a single marker.
struct Timeline<Strip: View>: View {
    let duration: Double
    @Binding var start: Double
    /// nil turns the timeline into a single-marker picker (for Split).
    var end: Binding<Double>?
    var playhead: Double?
    @ViewBuilder var strip: Strip

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width, height = geometry.size.height
            let x = { (time: Double) in duration > 0 ? CGFloat(time / duration) * width : 0 }
            ZStack(alignment: .topLeading) {
                strip
                    .frame(width: width, height: height)
                    .clipShape(.rect(cornerRadius: 10))
                if let end {
                    Rectangle().fill(.black.opacity(0.45)).frame(width: x(start), height: height)
                    Rectangle().fill(.black.opacity(0.45))
                        .frame(width: max(width - x(end.wrappedValue), 0), height: height)
                        .offset(x: x(end.wrappedValue))
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.limeDeep, lineWidth: 3)
                        .frame(width: max(x(end.wrappedValue) - x(start), 0), height: height)
                        .offset(x: x(start))
                        .allowsHitTesting(false)
                    handle(height).position(x: x(start), y: height / 2)
                        .gesture(drag(width) { start = min($0, end.wrappedValue - 0.1) })
                    handle(height).position(x: x(end.wrappedValue), y: height / 2)
                        .gesture(drag(width) { end.wrappedValue = max($0, start + 0.1) })
                } else {
                    Capsule().fill(Theme.limeDeep).frame(width: 4, height: height + 12)
                        .position(x: x(start), y: height / 2)
                    handle(height).position(x: x(start), y: height / 2)
                        .gesture(drag(width) { start = $0 })
                }
                if let playhead {
                    Rectangle().fill(.white).frame(width: 2, height: height)
                        .offset(x: x(playhead))
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "timeline")
        }
    }

    private func handle(_ height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Theme.limeDeep)
            .frame(width: 16, height: height)
            .overlay(Capsule().fill(.white).frame(width: 3, height: height * 0.35))
            .contentShape(Rectangle().inset(by: -6))
    }

    private func drag(_ width: CGFloat, _ update: @escaping (Double) -> Void) -> some Gesture {
        DragGesture(coordinateSpace: .named("timeline"))
            .onChanged { value in
                update(min(max(Double(value.location.x / width) * duration, 0), duration))
            }
    }
}

struct ThumbnailStrip: View {
    let images: [CGImage]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(images.indices, id: \.self) { index in
                Image(decorative: images[index], scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .background(.black.opacity(0.6))
    }
}

struct WaveformView: View {
    let peaks: [Float]

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty else { return }
            let step = size.width / CGFloat(peaks.count)
            var path = Path()
            for (index, peak) in peaks.enumerated() {
                let height = max(CGFloat(peak) * size.height * 0.92, 1)
                path.addRoundedRect(in: CGRect(x: CGFloat(index) * step, y: (size.height - height) / 2,
                                               width: max(step * 0.6, 1), height: height),
                                    cornerSize: CGSize(width: 1, height: 1))
            }
            context.fill(path, with: .color(Theme.limeDeep))
        }
        .background(.white.opacity(0.3))
    }
}

// MARK: - Video: trim & split

struct VideoTrimEditor: View {
    enum Mode { case trim, split }

    let url: URL
    let mode: Mode
    @ObservedObject var session: EditorSession
    @State private var player: AVPlayer
    @State private var duration = 0.0
    @State private var start = 0.0
    @State private var end = 0.0
    @State private var thumbnails: [CGImage] = []
    @State private var stopAt: Double?

    init(url: URL, mode: Mode, session: EditorSession) {
        self.url = url
        self.mode = mode
        self.session = session
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        EditorShell(title: mode == .trim ? "Trim Video" : "Split Video", session: session,
                    applyTitle: mode == .trim ? "Apply" : "Split", canApply: duration > 0, onApply: apply) {
            VStack(spacing: 12) {
                PreviewBox { VideoPlayer(player: player) }
                    .frame(height: 280)
                HStack {
                    Text(mode == .trim ? "Drag the ends to trim" : "Drag to where it should split")
                    Spacer()
                    Text(mode == .trim ? "\(formatTime(end - start)) selected" : "at \(formatTime(start))")
                        .monospacedDigit()
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                Timeline(duration: duration, start: $start, end: mode == .trim ? $end : nil) {
                    ThumbnailStrip(images: thumbnails)
                }
                .frame(height: 64)
                if mode == .trim {
                    HStack {
                        Text("Start \(formatTime(start))")
                        Spacer()
                        Text("End \(formatTime(end))")
                    }
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                }
            }
        } controls: {
            Button {
                playSelection()
            } label: {
                Label(mode == .trim ? "Play Selection" : "Play From Here", systemImage: "play.fill")
            }
            .buttonStyle(GlassPillButtonStyle())
        }
        .task {
            duration = (try? await VideoTools.duration(url)) ?? 0
            start = mode == .trim ? 0 : duration / 2
            end = duration
            thumbnails = await VideoTools.thumbnails(url, count: 10, height: 64)
        }
        .onChange(of: start) { seek(start) }
        .onChange(of: end) { seek(end) }
        .task(id: stopAt) {
            // Stop playback at the end of the selection.
            guard let stopAt else { return }
            while !Task.isCancelled, player.rate > 0 {
                if player.currentTime().seconds >= stopAt { player.pause(); break }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
        .onDisappear { player.pause() }
    }

    private func seek(_ time: Double) {
        player.pause()
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func playSelection() {
        player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
        stopAt = mode == .trim ? end : duration
    }

    private func apply() {
        player.pause()
        let url = url, start = start, end = end
        if mode == .trim {
            session.apply { [try await VideoTools.trim(url, from: start, to: end)] }
        } else {
            session.apply { try await VideoTools.split(url, at: start) }
        }
    }
}

// MARK: - Video: crop

struct VideoCropEditor: View {
    let url: URL
    @ObservedObject var session: EditorSession
    @State private var frame: CGImage?
    @State private var size = CGSize.zero
    @State private var aspect = CropAspect.square
    @State private var rect = CGRect(x: 0, y: 0, width: 1, height: 1)

    private let choices: [CropAspect] = [.square, .fourFive, .nineSixteen, .sixteenNine, .fourThree, .free]

    var body: some View {
        EditorShell(title: "Crop Video", session: session, canApply: frame != nil, onApply: apply) {
            VStack(spacing: 14) {
                PreviewBox {
                    GeometryReader { geometry in
                        let fit = fittedRect(size, in: geometry.size)
                        if let frame {
                            ZStack {
                                Image(decorative: frame, scale: 1).resizable()
                                CropOverlay(rect: $rect, pixelSize: size, ratio: aspect.ratio(original: size))
                            }
                            .frame(width: fit.width, height: fit.height)
                            .position(x: fit.midX, y: fit.midY)
                        }
                    }
                }
                .frame(height: 380)
                Picker("Aspect", selection: $aspect) {
                    ForEach(choices) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("\(Int(rect.width * size.width)) × \(Int(rect.height * size.height))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .onChange(of: aspect) { rect = CropOverlay.fullRect(ratio: aspect.ratio(original: size), pixelSize: size) }
        .task {
            size = (try? await VideoTools.displaySize(url)) ?? .zero
            frame = try? await VideoTools.frame(url, at: 0.5)
            rect = CropOverlay.fullRect(ratio: aspect.ratio(original: size), pixelSize: size)
        }
    }

    private func apply() {
        let url = url, rect = rect
        session.apply { [try await VideoTools.crop(url, to: rect)] }
    }
}

// MARK: - Video: speed

struct SpeedEditor: View {
    let url: URL
    @ObservedObject var session: EditorSession
    @State private var factor = 2.0
    @State private var keepAudio = true
    @State private var duration = 0.0

    private let speeds: [Double] = [0.25, 0.5, 0.75, 1.25, 1.5, 2, 4]

    var body: some View {
        EditorShell(title: "Change Speed", session: session, onApply: apply) {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle("Speed")
                Picker("Speed", selection: $factor) {
                    ForEach(speeds, id: \.self) { Text(String(format: "%g×", $0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Toggle("Keep the sound (pitch stays natural)", isOn: $keepAudio)
                    .toggleStyle(.checkbox)
                HStack {
                    Text("Now \(formatTime(duration))")
                    Spacer()
                    Text("Becomes \(formatTime(duration / factor))")
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .padding(12)
                .background(.white.opacity(0.35), in: .rect(cornerRadius: 12))
            }
        }
        .task { duration = (try? await VideoTools.duration(url)) ?? 0 }
    }

    private func apply() {
        let url = url, factor = factor, keepAudio = keepAudio
        session.apply { [try await VideoTools.changeSpeed(url, factor: factor, keepAudio: keepAudio)] }
    }
}

// MARK: - Video: compress

struct VideoCompressEditor: View {
    let urls: [URL]
    @ObservedObject var session: EditorSession
    @State private var preset = VideoTools.CompressPreset.all[2]
    @State private var hevc = false
    @State private var estimate: Int64?

    private var originalBytes: Int64 {
        Int64((try? urls[0].resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    var body: some View {
        EditorShell(title: "Compress Video", session: session, onApply: apply) {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle("Resolution")
                Picker("Resolution", selection: $preset) {
                    ForEach(VideoTools.CompressPreset.all, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Toggle("Use HEVC (smaller files, newer devices)", isOn: $hevc)
                    .toggleStyle(.checkbox)
                    .disabled(preset.hevcPreset == nil)
                HStack {
                    Text("Original \(ByteCountFormatter.string(fromByteCount: originalBytes, countStyle: .file))")
                    Spacer()
                    if let estimate {
                        Text("New ≈ \(ByteCountFormatter.string(fromByteCount: estimate, countStyle: .file))")
                    } else {
                        Text("Estimating…")
                    }
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .padding(12)
                .background(.white.opacity(0.35), in: .rect(cornerRadius: 12))
            }
        } controls: {
            if urls.count > 1 { Text("\(urls.count) videos").font(.caption.weight(.semibold)) }
        }
        .task(id: "\(preset.label)-\(hevc)") {
            estimate = nil
            estimate = await VideoTools.estimatedSize(urls[0], preset: preset.name(hevc: hevc))
        }
    }

    private func apply() {
        let urls = urls, name = preset.name(hevc: hevc)
        session.apply {
            var outputs: [URL] = []
            for (index, url) in urls.enumerated() {
                let share = 1 / Double(urls.count)
                outputs.append(try await JobProgress.$span.withValue(Double(index) * share...Double(index + 1) * share) {
                    try await VideoTools.compress(url, preset: name)
                })
            }
            return outputs
        }
    }
}

// MARK: - Audio: trim

struct AudioTrimEditor: View {
    let url: URL
    @ObservedObject var session: EditorSession
    @State private var peaks: [Float] = []
    @State private var duration = 0.0
    @State private var start = 0.0
    @State private var end = 0.0
    @State private var trimSilence = false
    @State private var player: AVAudioPlayer?
    @State private var playhead: Double?

    var body: some View {
        EditorShell(title: "Trim Audio", session: session, canApply: duration > 0, onApply: apply) {
            VStack(spacing: 12) {
                HStack {
                    Text("Drag the ends to trim")
                    Spacer()
                    Text("\(formatTime(end - start)) selected").monospacedDigit()
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                Timeline(duration: duration, start: $start, end: $end, playhead: playhead) {
                    WaveformView(peaks: peaks)
                }
                .frame(height: 170)
                HStack {
                    Text("Start \(formatTime(start))")
                    Spacer()
                    Text("End \(formatTime(end))")
                }
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                Toggle("Trim silent ends automatically", isOn: $trimSilence)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } controls: {
            Button {
                playSelection()
            } label: {
                Label(player?.isPlaying == true ? "Stop" : "Play Selected Range", systemImage: player?.isPlaying == true ? "stop.fill" : "play.fill")
            }
            .buttonStyle(GlassPillButtonStyle())
        }
        .task {
            let url = url
            if let wave = try? await offMain({ try AudioTools.waveform(url, bins: 300) }) {
                peaks = wave.peaks
                duration = wave.duration
                end = wave.duration
            }
            player = try? AVAudioPlayer(contentsOf: url)
        }
        .onChange(of: trimSilence) {
            let bounds = trimSilence ? AudioTools.soundBounds(peaks) : 0...1
            start = bounds.lowerBound * duration
            end = bounds.upperBound * duration
        }
        .onDisappear { player?.stop() }
    }

    private func playSelection() {
        guard let player else { return }
        if player.isPlaying {
            player.stop()
            playhead = nil
            return
        }
        player.currentTime = start
        player.play()
        Task {
            while player.isPlaying, player.currentTime < end {
                playhead = player.currentTime
                try? await Task.sleep(for: .milliseconds(30))
            }
            player.stop()
            playhead = nil
        }
    }

    private func apply() {
        player?.stop()
        let url = url, start = start, end = end
        session.apply { [try await offMain { try AudioTools.trim(url, from: start, to: end) }] }
    }
}

// MARK: - Audio: channels

struct ChannelsEditor: View {
    let url: URL
    @ObservedObject var session: EditorSession
    @State private var mono = true
    @State private var left = 1.0
    @State private var right = 1.0
    @State private var sourceChannels = 0
    @State private var player: AVAudioPlayer?

    var body: some View {
        EditorShell(title: "Convert Audio Channels", session: session, onApply: apply) {
            VStack(alignment: .leading, spacing: 16) {
                Text(sourceChannels == 1 ? "This file is mono." : sourceChannels == 2 ? "This file is stereo." : "")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Picker("Output", selection: $mono) {
                    Text("Mono").tag(true)
                    Text("Stereo").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                SliderRow(title: "Left", value: $left, range: 0...1.5, defaultValue: 1) { "\(Int($0 * 100))%" }
                SliderRow(title: "Right", value: $right, range: 0...1.5, defaultValue: 1) { "\(Int($0 * 100))%" }
            }
        } controls: {
            Button {
                if player?.isPlaying == true { player?.stop() } else { player?.currentTime = 0; player?.play() }
            } label: {
                Label("Play Original", systemImage: "play.fill")
            }
            .buttonStyle(GlassPillButtonStyle())
        }
        .task {
            sourceChannels = Int((try? AVAudioFile(forReading: url))?.fileFormat.channelCount ?? 0)
            mono = sourceChannels != 1
            player = try? AVAudioPlayer(contentsOf: url)
        }
        .onDisappear { player?.stop() }
    }

    private func apply() {
        player?.stop()
        let url = url, mono = mono, left = Float(left), right = Float(right)
        session.apply { [try await offMain { try AudioTools.channels(url, mono: mono, left: left, right: right) }] }
    }
}
