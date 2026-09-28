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
                    sourceRow(for: item)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.insetGrouped)
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

    // MARK: - Row

    @ViewBuilder
    private func sourceRow(for item: HomeMediaItem) -> some View {
        HStack(spacing: 12) {
            // Poster thumbnail
            posterThumbnail(for: item)
                .frame(width: 48, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(sourceLabel(for: item))
                    .font(.headline)
                    .foregroundStyle(themeManager.colors.primaryText)

                HStack(spacing: 6) {
                    sourceTypeBadge(for: item)
                    if let quality = qualityHint(for: item) {
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

    @ViewBuilder
    private func posterThumbnail(for item: HomeMediaItem) -> some View {
        switch item {
        case .movie(let movie):
            CachedAsyncImage(url: movie.streamIcon.flatMap(URL.init(string:))) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.3)
            }
        case .series(let series):
            CachedAsyncImage(url: series.cover.flatMap(URL.init(string:))) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.3)
            }
        default:
            Color.gray.opacity(0.3)
        }
    }

    // MARK: - Labels

    private func sourceLabel(for item: HomeMediaItem) -> String {
        let ownerID = ownerUUID(from: item.id)
        // Check playlists first
        if let playlist = playlists.first(where: { $0.id.uuidString == ownerID }) {
            return playlist.name
        }
        // Then media servers
        if let server = mediaServers.first(where: { $0.id.uuidString == ownerID }) {
            return server.name
        }
        return "Unknown Source"
    }

    @ViewBuilder
    private func sourceTypeBadge(for item: HomeMediaItem) -> some View {
        let ownerID = ownerUUID(from: item.id)
        if let playlist = playlists.first(where: { $0.id.uuidString == ownerID }) {
            Text(playlist.sourceType.displayName)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(themeManager.colors.accent.opacity(0.2))
                .clipShape(Capsule())
                .foregroundStyle(themeManager.colors.accent)
        } else if let server = mediaServers.first(where: { $0.id.uuidString == ownerID }) {
            Text(server.kind.displayName)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.2))
                .clipShape(Capsule())
                .foregroundStyle(.orange)
        }
    }

    private func qualityHint(for item: HomeMediaItem) -> String? {
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
}

// MARK: - Display name helpers

private extension PlaylistSourceType {
    var displayName: String {
        switch self {
        case .xtream: "Xtream"
        case .m3u: "M3U"
        case .stalker: "Stalker"
        }
    }
}

private extension MediaServerKind {
    var displayName: String {
        switch self {
        case .jellyfin: "Jellyfin"
        case .emby: "Emby"
        case .plex: "Plex"
        }
    }
}