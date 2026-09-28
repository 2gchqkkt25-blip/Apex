//
//  CrossSourcePickerView.swift
//  Apex
//
//  A modal sheet that lets users choose which configured source (playlist or
//  media server) to play a movie or series from when the same title exists
//  in multiple places. Each row shows the source name, type badge, and
//  quality/resolution hint when available.
//

import SwiftData
import SwiftUI

struct CrossSourcePickerView: View {
    let items: [HomeMediaItem]
    let currentID: String
    let onSelect: (HomeMediaItem) -> Void
    let onCancel: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Query private var playlists: [Playlist]
    @Query private var mediaServers: [MediaServer]

    var body: some View {
        NavigationStack {
            List(items) { item in
                Button {
                    onSelect(item)
                } label: {
                    CrossSourceRow(
                        item: item,
                        isCurrent: item.id == currentID,
                        playlistName: playlistName(for: item),
                        serverName: serverName(for: item),
                        sourceTypeLabel: sourceTypeLabel(for: item),
                        isMediaServer: isMediaServerSource(for: item),
                        qualityHint: qualityHint(for: item),
                        posterURL: posterURL(for: item),
                        theme: themeManager.colors
                    )
                }
                .buttonStyle(.plain)
            }
            #if os(macOS)
            .listStyle(.inset)
            #else
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("Choose Source")
            #if os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    // MARK: - Data helpers (pure functions, no view building)

    private func ownerUUID(for item: HomeMediaItem) -> String? {
        let id = item.id
        if let range = id.range(of: "-movie-") { return String(id[id.startIndex..<range.lowerBound]) }
        if let range = id.range(of: "-series-") { return String(id[id.startIndex..<range.lowerBound]) }
        if let range = id.range(of: "-episode-") { return String(id[id.startIndex..<range.lowerBound]) }
        return nil
    }

    private func playlistName(for item: HomeMediaItem) -> String? {
        guard let uuid = ownerUUID(for: item) else { return nil }
        return playlists.first(where: { $0.id.uuidString == uuid })?.name
    }

    private func serverName(for item: HomeMediaItem) -> String? {
        guard let uuid = ownerUUID(for: item) else { return nil }
        return mediaServers.first(where: { $0.id.uuidString == uuid })?.name
    }

    private func isMediaServerSource(for item: HomeMediaItem) -> Bool {
        guard let uuid = ownerUUID(for: item) else { return false }
        return mediaServers.contains(where: { $0.id.uuidString == uuid })
    }

    private func sourceTypeLabel(for item: HomeMediaItem) -> String? {
        guard let uuid = ownerUUID(for: item) else { return nil }
        if let playlist = playlists.first(where: { $0.id.uuidString == uuid }) {
            switch playlist.sourceType {
            case .xtream: return "Xtream"
            case .m3u: return "M3U"
            case .stalker: return "Stalker"
            }
        }
        if let server = mediaServers.first(where: { $0.id.uuidString == uuid }) {
            return server.kind.displayName
        }
        return nil
    }

    private func qualityHint(for item: HomeMediaItem) -> String? {
        switch item {
        case .movie(let m):
            guard let d = m.durationSecs, d > 0 else { return nil }
            return "\(d / 60) min"
        case .series(let s):
            guard let y = s.releaseDate?.prefix(4) else { return nil }
            return String(y)
        default:
            return nil
        }
    }

    private func posterURL(for item: HomeMediaItem) -> URL? {
        switch item {
        case .movie(let m): return m.streamIcon.flatMap(URL.init(string:))
        case .series(let s): return s.cover.flatMap(URL.init(string:))
        default: return nil
        }
    }
}

// MARK: - Row (fully self-contained, no @Query or environment lookups)

private struct CrossSourceRow: View {
    let item: HomeMediaItem
    let isCurrent: Bool
    let playlistName: String?
    let serverName: String?
    let sourceTypeLabel: String?
    let isMediaServer: Bool
    let qualityHint: String?
    let posterURL: URL?
    let theme: ThemeColors

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(url: posterURL)
                .frame(width: 48, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)

                HStack(spacing: 6) {
                    if let label = sourceTypeLabel {
                        Badge(label: label, isMediaServer: isMediaServer, theme: theme)
                    }
                    if let q = qualityHint {
                        Text(q)
                            .font(.caption2)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }

            Spacer()

            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.accent)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }

    private var displayName: String {
        playlistName ?? serverName ?? "Unknown Source"
    }
}

// MARK: - Poster (isolated CachedAsyncImage to prevent parent diagnostic failure)

private struct PosterImage: View {
    let url: URL?

    var body: some View {
        CachedAsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .empty, .failure:
                Color.gray.opacity(0.3)
            @unknown default:
                Color.gray.opacity(0.3)
            }
        }
    }
}

// MARK: - Badge (trivial leaf view)

private struct Badge: View {
    let label: String
    let isMediaServer: Bool
    let theme: ThemeColors

    var body: some View {
        Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isMediaServer ? Color.orange.opacity(0.2) : theme.accent.opacity(0.2))
            .clipShape(Capsule())
            .foregroundStyle(isMediaServer ? .orange : theme.accent)
    }
}