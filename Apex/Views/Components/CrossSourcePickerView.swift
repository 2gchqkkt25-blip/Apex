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
                    SourceRowView(
                        item: item,
                        currentID: currentID,
                        playlists: playlists,
                        mediaServers: mediaServers,
                        themeManager: themeManager
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
}

// MARK: - Row View (extracted to avoid complex expression diagnostics)

private struct SourceRowView: View {
    let item: HomeMediaItem
    let currentID: String
    let playlists: [Playlist]
    let mediaServers: [MediaServer]
    let themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 12) {
            PosterThumbnailView(item: item)
                .frame(width: 48, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(sourceLabel)
                    .font(.headline)
                    .foregroundStyle(themeManager.colors.primaryText)

                HStack(spacing: 6) {
                    SourceTypeBadgeView(
                        item: item,
                        playlists: playlists,
                        mediaServers: mediaServers,
                        themeManager: themeManager
                    )
                    if let quality = qualityHint {
                        Text(quality)
                            .font(.caption2)
                            .foregroundStyle(themeManager.colors.secondaryText)
                    }
                }
            }

            Spacer()

            if item.id == currentID {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(themeManager.colors.accent)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }

    private var sourceLabel: String {
        let ownerID = ownerUUID(from: item.id)
        if let playlist = playlists.first(where: { $0.id.uuidString == ownerID }) {
            return playlist.name
        }
        if let server = mediaServers.first(where: { $0.id.uuidString == ownerID }) {
            return server.name
        }
        return "Unknown Source"
    }

    private var qualityHint: String? {
        switch item {
        case .movie(let movie):
            if let duration = movie.durationSecs, duration > 0 {
                return "\(duration / 60) min"
            }
            return nil
        case .series(let series):
            if let year = series.releaseDate?.prefix(4) {
                return String(year)
            }
            return nil
        default:
            return nil
        }
    }
}

// MARK: - Poster Thumbnail (extracted to isolate CachedAsyncImage usage)

private struct PosterThumbnailView: View {
    let item: HomeMediaItem

    var body: some View {
        Group {
            switch item {
            case .movie(let movie):
                if let url = movie.streamIcon.flatMap(URL.init(string:)) {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .empty:
                            Color.gray.opacity(0.3)
                        case .failure:
                            Color.gray.opacity(0.3)
                        @unknown default:
                            Color.gray.opacity(0.3)
                        }
                    }
                } else {
                    Color.gray.opacity(0.3)
                }
            case .series(let series):
                if let url = series.cover.flatMap(URL.init(string:)) {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .empty:
                            Color.gray.opacity(0.3)
                        case .failure:
                            Color.gray.opacity(0.3)
                        @unknown default:
                            Color.gray.opacity(0.3)
                        }
                    }
                } else {
                    Color.gray.opacity(0.3)
                }
            default:
                Color.gray.opacity(0.3)
            }
        }
    }
}

// MARK: - Source Type Badge (extracted to simplify parent expression)

private struct SourceTypeBadgeView: View {
    let item: HomeMediaItem
    let playlists: [Playlist]
    let mediaServers: [MediaServer]
    let themeManager: ThemeManager

    var body: some View {
        Group {
            if let playlist = matchingPlaylist {
                Text(playlist.sourceType.localizedName)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(themeManager.colors.accent.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundStyle(themeManager.colors.accent)
            } else if let server = matchingServer {
                Text(server.kind.displayName)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundStyle(.orange)
            }
        }
    }

    private var matchingPlaylist: Playlist? {
        guard let ownerID = ownerUUID(from: item.id) else { return nil }
        return playlists.first(where: { $0.id.uuidString == ownerID })
    }

    private var matchingServer: MediaServer? {
        guard let ownerID = ownerUUID(from: item.id) else { return nil }
        return mediaServers.first(where: { $0.id.uuidString == ownerID })
    }
}

// MARK: - Helpers

/// Extracts the owner UUID prefix from a content id like `<uuid>-movie-<streamId>`.
private func ownerUUID(from contentID: String) -> String? {
    let parts = contentID.components(separatedBy: "-movie-")
    if parts.count >= 2 { return parts[0] }
    let seriesParts = contentID.components(separatedBy: "-series-")
    if seriesParts.count >= 2 { return seriesParts[0] }
    let episodeParts = contentID.components(separatedBy: "-episode-")
    if episodeParts.count >= 2 { return episodeParts[0] }
    return nil
}

private extension PlaylistSourceType {
    var localizedName: String {
        switch self {
        case .xtream: "Xtream"
        case .m3u: "M3U"
        case .stalker: "Stalker"
        }
    }
}