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
                        Button(action: { onSelect(item) }) {
                            HStack(spacing: 12) {
                                PosterImage(url: posterURL(for: item))
                                    .frame(width: 48, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(displayName(for: item))
                                        .font(.headline)
                                        .foregroundStyle(themeManager.colors.primaryText)

                                    HStack(spacing: 6) {
                                        if let badge = badgeLabel(for: item) {
                                            BadgeView(
                                                label: badge,
                                                isMediaServer: isMediaServer(for: item),
                                                colors: themeManager.colors
                                            )
                                        }
                                        if let hint = qualityHint(for: item) {
                                            Text(hint)
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
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
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

    // MARK: - Pure data helpers (no @ViewBuilder, no closures over self)

    private func displayName(for item: HomeMediaItem) -> String {
        guard let uuid = ownerUUID(for: item) else { return "Unknown Source" }
        for p in playlists where p.id.uuidString == uuid { return p.name }
        for s in mediaServers where s.id.uuidString == uuid { return s.name }
        return "Unknown Source"
    }

    private func isMediaServer(for item: HomeMediaItem) -> Bool {
        guard let uuid = ownerUUID(for: item) else { return false }
        for s in mediaServers where s.id.uuidString == uuid { return true }
        return false
    }

    private func badgeLabel(for item: HomeMediaItem) -> String? {
        guard let uuid = ownerUUID(for: item) else { return nil }
        for p in playlists where p.id.uuidString == uuid {
            switch p.sourceType {
            case .xtream: return "Xtream"
            case .m3u: return "M3U"
            case .stalker: return "Stalker"
            }
        }
        for s in mediaServers where s.id.uuidString == uuid {
            return s.kind.displayName
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

    private func ownerUUID(for item: HomeMediaItem) -> String? {
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