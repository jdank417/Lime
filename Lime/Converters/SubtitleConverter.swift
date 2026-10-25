//
//  SubtitleConverter.swift
//  Lime
//

import Foundation

/// SRT ⇄ WebVTT, or plain text with the timings dropped.
nonisolated enum SubtitleConverter {
    struct Cue: Equatable, Sendable {
        /// "hh:mm:ss.mmm"
        let start: String
        let end: String
        let text: String
    }

    static let targets = [("SRT", "srt"), ("VTT", "vtt"), ("TXT", "txt")]

    static func convert(_ url: URL, to ext: String) throws -> URL {
        let cues = parse(try String(contentsOf: url, encoding: .utf8))
        guard !cues.isEmpty else { throw LimeError.failed("No subtitles found in \(url.lastPathComponent)") }
        let text = switch ext {
        case "srt": srt(cues)
        case "vtt": vtt(cues)
        default: cues.map(\.text).joined(separator: "\n")
        }
        let out = Output.url(for: url, ext: ext)
        try text.write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    static func parse(_ text: String) -> [Cue] {
        let blocks = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        return blocks.compactMap { block in
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let parts = lines[timing].components(separatedBy: "-->")
            // VTT may put cue settings ("align:start") after the end time.
            guard parts.count == 2, let start = time(parts[0]),
                  let end = time(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ")[0])
            else { return nil }
            let body = lines[(timing + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return Cue(start: start, end: end, text: body)
        }
    }

    static func srt(_ cues: [Cue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(cue.start.replacingOccurrences(of: ".", with: ",")) --> \(cue.end.replacingOccurrences(of: ".", with: ","))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    static func vtt(_ cues: [Cue]) -> String {
        "WEBVTT\n\n" + cues.map { "\($0.start) --> \($0.end)\n\($0.text)\n" }.joined(separator: "\n")
    }

    /// Accepts "1:02.5", "00:01:02,500" or "01:02.500"; returns "00:01:02.500".
    private static func time(_ raw: String) -> String? {
        let parts = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard (2...3).contains(parts.count), let seconds = Double(parts.last!) else { return nil }
        let numbers = parts.dropLast().compactMap { Int($0) }
        guard numbers.count == parts.count - 1 else { return nil }
        let hours = numbers.count == 2 ? numbers[0] : 0
        let minutes = numbers.last ?? 0
        return String(format: "%02d:%02d:%06.3f", hours, minutes, seconds)
    }
}
