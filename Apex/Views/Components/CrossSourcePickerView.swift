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
                    makeRow(for: item)
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

    // MARK: - Row factory (returns AnyView to break expression tree)

    private func makeRow(for item: HomeMediaItem) -> AnyView {
        let uuid = ownerUUID(for: item)
        let pName = uuid.flatMap { u in playlists.first(where: { $0.id.uuidString == u })?.name }
        let sName = uuid.flatMap { u in mediaServers.first(where: { $0.id.uuidString == u })?.name }
        let isMS = uuid.map { u in mediaServers.contains(where: { $0.id.uuidString == u }) } ?? false
        let label = sourceTypeLabel(for: item, uuid: uuid)
        let hint = qualityHint(for: item)
        let poster = posterURL(for: item)
        let isCur = item.id == currentID
        let colors = themeManager.colors

        return AnyView(
            HStack(spacing: 12) {
                PosterImage(url: poster)
                    .frame(width: 48, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    Text(pName ?? sName ?? "Unknown Source")
                        .font(.headline)
                        .foregroundStyle(colors.primaryText)

                    HStack(spacing: 6) {
                        if let l = label {
                            Badge(label: l, isMediaServer: isMS, theme: colors)
                        }
                        if let q = hint {
                            Text(q)
                                .font(.caption2)
                                .foregroundStyle(colors.secondaryText)
                        }
                    }
                }

                Spacer()

                if isCur {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(colors.accent)
                        .font(.title3)
                }
            }
            .padding(.vertical, 4)
        )
    }

    // MARK: - Data helpers

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

    private func sourceTypeLabel(for item: HomeMediaItem, uuid: String?) -> String? {
        guard let uuid else { return nil }
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