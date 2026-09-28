//
//  CrossSourcePickerView.swift
//  Apex
//
//  A modal sheet that lets users choose which configured source (playlist or
//  media server) to play a movie or series from when the same title exists
//  in multiple places.
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
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            RowContent(
                                item: item,
                                currentID: currentID,
                                playlists: playlists,
                                mediaServers: mediaServers,
                                colors: themeManager.colors
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 72)
                    }
                }
                .padding(.vertical, 8)
            }
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 300)
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

// MARK: - Row Content (standalone struct, no closures, no AnyView)

private struct RowContent: View {
    let item: HomeMediaItem
    let currentID: String
    let playlists: [Playlist]
    let mediaServers: [MediaServer]
    let colors: ThemeColors

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(url: posterURL)
                .frame(width: 48, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                    .foregroundStyle(colors.primaryText)

                HStack(spacing: 6) {
                    if let badge = badgeLabel {
                        BadgeView(
                            label: badge,
                            isMediaServer: isMediaServer,
                            colors: colors
                        )
                    }
                    if let hint = qualityHint {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(colors.secondaryText)
                    }
                }
            }

            Spacer()

            if item.id == currentID {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(colors.accent)
                    .font(.title3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Computed properties (simple, no nested expressions)

    private var ownerUUID: String? {
        switch item {
        case .movie(let m):
            let parts = m.id.components(separatedBy: "-movie-")
            return parts.count >= 2 ? parts[0] : nil
        case .series(let s):
            let parts = s.id.components(separatedBy: "-series-")
            return parts.count >= 2 ? parts[0] : nil
        default:
            return nil
        }
    }

    private var displayName: String {
        guard let uuid = ownerUUID else { return "Unknown Source" }
        if let p = playlists.first(where: { $0.id.uuidString == uuid }) {
            return p.name
        }
        if let s = mediaServers.first(where: { $0.id.uuidString == uuid }) {
            return s.name
        }
        return "Unknown Source"
    }

    private var isMediaServer: Bool {
        guard let uuid = ownerUUID else { return false }
        return mediaServers.contains(where: { $0.id.uuidString == uuid })
    }

    private var badgeLabel: String? {
        guard let uuid = ownerUUID else { return nil }
        if let p = playlists.first(where: { $0.id.uuidString == uuid }) {
            switch p.sourceType {
            case .xtream: return "Xtream"
            case .m3u: return "M3U"
            case .stalker: return "Stalker"
            }
        }
        if let s = mediaServers.first(where: { $0.id.uuidString == uuid }) {
            return s.kind.displayName
        }
        return nil
    }

    private var qualityHint: String? {
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

    private var posterURL: URL? {
        switch item {
        case .movie(let m): return m.streamIcon.flatMap(URL.init(string:))
        case .series(let s): return s.cover.flatMap(URL.init(string:))
        default: return nil
        }
    }
}

// MARK: - Poster (isolated CachedAsyncImage)

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

private struct BadgeView: View {
    let label: String
    let isMediaServer: Bool
    let colors: ThemeColors

    var body: some View {
        Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isMediaServer ? Color.orange.opacity(0.2) : colors.accent.opacity(0.2))
            .clipShape(Capsule())
            .foregroundStyle(isMediaServer ? .orange : colors.accent)
    }
}