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
                        rowButton(for: item)
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

    // MARK: - Row button (broken out to reduce body complexity)

    @ViewBuilder
    private func rowButton(for item: HomeMediaItem) -> some View {
        let uuid = ownerUUID(for: item)
        let pName = playlistName(uuid: uuid)
        let sName = serverName(uuid: uuid)
        let badge = badgeLabel(uuid: uuid)
        let isMS = isMediaServer(uuid: uuid)
        let hint = qualityHint(for: item)
        let poster = posterURL(for: item)
        let isCur = item.id == currentID
        let c = themeManager.colors

        Button {
            onSelect(item)
        } label: {
            HStack(spacing: 12) {
                PosterImage(url: poster)
                    .frame(width: 48, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    Text(pName ?? sName ?? "Unknown Source")
                        .font(.headline)
                        .foregroundStyle(c.primaryText)

                    HStack(spacing: 6) {
                        if let b = badge {
                            BadgeView(label: b, isMediaServer: isMS, colors: c)
                        }
                        if let h = hint {
                            Text(h)
                                .font(.caption2)
                                .foregroundStyle(c.secondaryText)
                        }
                    }
                }

                Spacer()

                if isCur {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(c.accent)
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pure data helpers (no view building)

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

    private func playlistName(uuid: String?) -> String? {
        guard let uuid else { return nil }
        return playlists.first(where: { $0.id.uuidString == uuid })?.name
    }

    private func serverName(uuid: String?) -> String? {
        guard let uuid else { return nil }
        return mediaServers.first(where: { $0.id.uuidString == uuid })?.name
    }

    private func isMediaServer(uuid: String?) -> Bool {
        guard let uuid else { return false }
        return mediaServers.contains(where: { $0.id.uuidString == uuid })
    }

    private func badgeLabel(uuid: String?) -> String? {
        guard let uuid else { return nil }
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