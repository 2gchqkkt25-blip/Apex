//
//  ExternalSubtitleOverlay.swift
//  Apex
//
//  Renders external SRT subtitles over the video player, synced to the
//  PlaybackClock. Works with any engine (KSPlayer, VLC, AVPlayer) since it
//  reads the clock's current time independently.
//

import OSLog
import SwiftUI

/// Parses and renders an SRT subtitle file, displaying cues based on playback time.
struct ExternalSubtitleOverlay: View {
    let subtitleURL: URL
    @Bindable var clock: PlaybackClock
    var controlsVisible = false

    @State private var cues: [SRTCue] = []
    @State private var currentText: String = ""
    @State private var pollTimer: Timer?

    private let appearance = SubtitleAppearance.current

    var body: some View {
        SubtitleOverlayLayout(appearance: appearance, controlsVisible: controlsVisible) {
            if !currentText.isEmpty {
                Text(currentText)
                    .font(.system(size: appearance.fontSize, weight: .medium))
                    .foregroundStyle(appearance.textColor)
                    .shadow(color: .black.opacity(0.9), radius: 2, x: 1, y: 1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(.black.opacity(appearance.backgroundOpacity), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .task {
            cues = SRTParser.parse(fileURL: subtitleURL)
            if cues.isEmpty {
                Logger.player.warning("[Subtitles] SRT parser returned 0 cues from \(subtitleURL.lastPathComponent)")
            } else {
                Logger.player.info("[Subtitles] Parsed \(cues.count) subtitle cues")
            }
        }
        .onChange(of: clock.current) { _, time in
            updateCurrentCue(at: time)
        }
        .onAppear {
            // Poll as a fallback in case onChange doesn't fire reliably
            // (some engine/clock combos update on a non-main dispatch queue
            // and the Observation change may not propagate every tick)
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
                updateCurrentCue(at: clock.current)
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
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

        // Normalize line endings: \r\n → \n, standalone \r → \n
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Remove BOM if present
        let cleaned = normalized.hasPrefix("\u{FEFF}") ? String(normalized.dropFirst()) : normalized

        let blocks = cleaned.components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard lines.count >= 2 else { continue }

            // Find the timestamp line (contains " --> ")
            // Some SRT files have extra blank lines or metadata before the index
            var timestampLineIndex: Int?
            for (lineIndex, line) in lines.enumerated() where line.contains(" --> ") {
                timestampLineIndex = lineIndex
                break
            }
            guard let tsIdx = timestampLineIndex, tsIdx + 1 < lines.count else { continue }

            // Parse index (line before timestamp, if available)
            let index: Int = if tsIdx > 0, let parsed = Int(lines[tsIdx - 1]) {
                parsed
            } else {
                cues.count + 1
            }

            // Parse timestamps "00:01:23,456 --> 00:01:26,789"
            let timeParts = lines[tsIdx].components(separatedBy: " --> ")
            guard timeParts.count == 2,
                  let start = parseTimestamp(timeParts[0]),
                  let end = parseTimestamp(timeParts[1])
            else { continue }

            // Remaining lines after the timestamp: subtitle text
            let textLines = lines[(tsIdx + 1)...]
            let text = textLines.joined(separator: "\n")
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

/// Make SRTCue usable in SwiftUI
extension SRTParser.SRTCue: Identifiable {
    var id: Int {
        index
    }
}

typealias SRTCue = SRTParser.SRTCue
