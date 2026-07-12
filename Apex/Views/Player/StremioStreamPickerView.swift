//
//  StremioStreamPickerView.swift
//  Apex
//
//  Shows all available Stremio streams from all configured addons, ranked by
//  quality. The user can tap a stream to play it, or use the "Play Best" button
//  to auto-select the highest quality option — matching the Stremio desktop UX.
//

import SwiftUI

struct StremioStreamPickerView: View {
    let streams: [StremioStreamOption]
    let onSelect: (StremioStreamOption) -> Void
    let onCancel: () -> Void

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        NavigationStack {
            List {
                if let best = streams.first {
                    Section {
                        Button(action: { onSelect(best) }) {
                            HStack(spacing: 12) {
                                Image(systemName: "bolt.fill")
                                    .foregroundStyle(.yellow)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Play Best Quality")
                                        .font(.headline)
                                    Text(best.displayTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                qualityBadge(for: best)
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("Recommended")
                    }
                }

                Section {
                    ForEach(streams) { stream in
                        Button(action: { onSelect(stream) }) {
                            streamRow(stream)
                        }
                    }
                } header: {
                    Text("\(streams.count) streams available")
                }
            }
            .navigationTitle("Select Stream")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private func streamRow(_ stream: StremioStreamOption) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(stream.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                if let detail = stream.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let addon = stream.addonName {
                    Text(addon)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            qualityBadge(for: stream)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func qualityBadge(for stream: StremioStreamOption) -> some View {
        if let quality = stream.qualityLabel {
            Text(quality)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(qualityColor(for: quality).opacity(0.15))
                .foregroundStyle(qualityColor(for: quality))
                .clipShape(Capsule())
        }
    }

    private func qualityColor(for quality: String) -> Color {
        let q = quality.lowercased()
        if q.contains("4k") || q.contains("2160") { return .purple }
        if q.contains("1080") { return .blue }
        if q.contains("720") { return .green }
        return .secondary
    }
}

// MARK: - Stream Option Model

/// A resolved stream option presented to the user in the picker.
struct StremioStreamOption: Identifiable {
    let id = UUID()
    let url: URL
    let displayTitle: String
    let detail: String?
    let qualityLabel: String?
    let addonName: String?
    let score: Int

    init(stream: StremioStream, addonName: String?, score: Int) {
        self.url = stream.bestURL ?? URL(string: "about:blank")!
        self.displayTitle = stream.displayTitle
        self.addonName = addonName
        self.score = score

        // Extract quality label from the stream title/name
        let text = ((stream.title ?? "") + " " + (stream.name ?? "")).lowercased()
        if text.contains("2160p") || text.contains("4k") || text.contains("uhd") {
            qualityLabel = "4K"
        } else if text.contains("1080p") || text.contains("1080") {
            qualityLabel = "1080p"
        } else if text.contains("720p") || text.contains("720") {
            qualityLabel = "720p"
        } else if text.contains("480p") {
            qualityLabel = "480p"
        } else {
            qualityLabel = nil
        }

        // Build detail line (codec + size)
        var details: [String] = []
        if text.contains("hevc") || text.contains("x265") || text.contains("h265") || text.contains("h.265") {
            details.append("HEVC")
        } else if text.contains("h.264") || text.contains("x264") || text.contains("h264") {
            details.append("H.264")
        }
        if text.contains("hdr") || text.contains("dolby vision") {
            details.append("HDR")
        }
        // Try to extract file size
        if let range = text.range(of: #"\d+\.?\d*\s*gb"#, options: .regularExpression) {
            details.append(String(text[range]).uppercased())
        } else if let range = text.range(of: #"\d+\.?\d*\s*mb"#, options: .regularExpression) {
            details.append(String(text[range]).uppercased())
        }
        self.detail = details.isEmpty ? nil : details.joined(separator: " · ")
    }
}
