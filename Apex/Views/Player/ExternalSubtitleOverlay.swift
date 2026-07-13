//
//  ExternalSubtitleOverlay.swift
//  Apex
//
//  Renders external SRT subtitles over the video player, synced to the
//  PlaybackClock. Works with any engine (KSPlayer, VLC, AVPlayer) since it
//  reads the clock's current time independently.
//

import SwiftUI

/// Parses and renders an SRT subtitle file, displaying cues based on playback time.
struct ExternalSubtitleOverlay: View {
    let subtitleURL: URL
    @Bindable var clock: PlaybackClock

    @State private var cues: [SRTCue] = []
    @State private var currentText: String = ""

    var body: some View {
        VStack {
            Spacer()
            if !currentText.isEmpty {
                Text(currentText)
                    .font(.system(size: subtitleFontSize, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.9), radius: 2, x: 1, y: 1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.bottom, bottomPadding)
            }
        }
        .allowsHitTesting(false)
        .task {
            cues = SRTParser.parse(fileURL: subtitleURL)
        }
        .onChange(of: clock.current) { _, time in
            updateCurrentCue(at: time)
        }
    }

    private var subtitleFontSize: CGFloat {
        #if os(tvOS)
        28
        #else
        17
        #endif
    }

    private var bottomPadding: CGFloat {
        #if os(tvOS)
        60
        #else
        40
        #endif
    }

    private func updateCurrentCue(at time: TimeInterval) {
        // Find the cue that spans the current playback time
        if let cue = cues.first(where: { time >= $0.start && time <= $0.end }) {
            if currentText != cue.text {
                currentText = cue.text
            }
        } else if !currentText.isEmpty {
            currentText = ""
        }
    }
}

// MARK: - SRT Parser

enum SRTParser {
    struct SRTCue {
        let index: Int
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }

    /// Parses an SRT file into an array of timed cues.
    static func parse(fileURL: URL) -> [SRTCue] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return parse(content: content)
    }

    static func parse(content: String) -> [SRTCue] {
        var cues: [SRTCue] = []
        let blocks = content.components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard lines.count >= 3 else { continue }

            // First line: cue index
            guard let index = Int(lines[0]) else { continue }

            // Second line: timestamps "00:01:23,456 --> 00:01:26,789"
            let timeParts = lines[1].components(separatedBy: " --> ")
            guard timeParts.count == 2,
                  let start = parseTimestamp(timeParts[0]),
                  let end = parseTimestamp(timeParts[1])
            else { continue }

            // Remaining lines: subtitle text
            let text = lines[2...].joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            cues.append(SRTCue(index: index, start: start, end: end, text: text))
        }

        return cues.sorted { $0.start < $1.start }
    }

    /// Parses "HH:MM:SS,mmm" into seconds.
    private static func parseTimestamp(_ str: String) -> TimeInterval? {
        let cleaned = str.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.components(separatedBy: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2])
        else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}

// Make SRTCue usable in SwiftUI
extension SRTParser.SRTCue: Identifiable {
    var id: Int { index }
}

typealias SRTCue = SRTParser.SRTCue
