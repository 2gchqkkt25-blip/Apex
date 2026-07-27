//
//  LiveChannelNavigator.swift
//  Apex
//
//  Resolves the channel to surf to when the viewer asks for the next/previous
//  live stream from inside the player (the tvOS player drives this from up/down
//  on the Siri Remote). Kept as pure, cross-platform data resolution — no view
//  state — so it can be unit-tested independently of any UI.
//

import Foundation
import SwiftData

enum LiveChannelNavigator {
    /// The scope the current live playback was launched from. Set by the Live TV
    /// view when the user starts playback from Favorites or Recently Watched,
    /// so channel surfing stays within that collection. Reset to nil when
    /// playback starts from a regular category.
    nonisolated(unsafe) static var activeSurfScope: LiveChannelScope?

    /// The playlist that owns a live stream. Stream `id`s are prefixed with the
    /// owning playlist's UUID at sync time (see `ContentSyncManager`).
    static func playlist(for stream: LiveStream, in context: ModelContext) -> Playlist? {
        let playlists = (try? context.fetch(FetchDescriptor<Playlist>())) ?? []
        return playlists.first { stream.id.hasPrefix($0.id.uuidString) } ?? playlists.first
    }

    /// The playable channel `offset` positions away from `media` within its
    /// category, honouring `sort` so the order matches the channel list the
    /// viewer browsed. `offset` is `+1` for the next channel and `-1` for the
    /// previous; the list wraps at the category's ends so surfing never
    /// dead-ends. Returns `nil` when `media` isn't a resolvable live stream or
    /// its category holds a single channel.
    ///
    /// When `scope` is `.favorites`, surfs through the user's favorited channels
    /// instead of the category list — matching what the viewer was browsing.
    ///
    /// All scopes filter to the current stream's owning playlist so channel
    /// surfing never crosses into a different playlist's channels.
    static func adjacentMedia(
        for media: PlayableMedia,
        offset: Int,
        sort: ContentSortOption,
        scope: LiveChannelScope? = nil,
        in context: ModelContext
    ) -> PlayableMedia? {
        guard case let .live(id) = media.contentRef else { return nil }
        let streams = fetchSurfChannels(for: media, sort: sort, scope: scope, in: context)
        guard streams.count > 1,
              let index = streams.firstIndex(where: { $0.id == id }) else { return nil }

        let target = streams[(index + offset + streams.count) % streams.count]
        guard let playlist = playlist(for: target, in: context) else { return nil }
        return PlayableMedia.from(stream: target, playlist: playlist)
    }

    /// Channels available for the in-player Guide panel. Same scope/sort as
    /// `adjacentMedia`, but capped and centred on the playing channel so the
    /// overlay stays viewport-sized.
    static func surfChannels(
        for media: PlayableMedia,
        sort: ContentSortOption,
        scope: LiveChannelScope? = nil,
        limit: Int = 40,
        in context: ModelContext
    ) -> [LiveStream] {
        guard case let .live(id) = media.contentRef else { return [] }
        let streams = fetchSurfChannels(for: media, sort: sort, scope: scope, in: context)
        guard let index = streams.firstIndex(where: { $0.id == id }) else {
            return Array(streams.prefix(limit))
        }
        let half = limit / 2
        let start = max(0, min(index - half, streams.count - min(limit, streams.count)))
        let end = min(streams.count, start + limit)
        return Array(streams[start ..< end])
    }

    /// Full surf list for the active scope (uncapped beyond fetch limits). Used
    /// by channel up/down; the Guide windows this further via `surfChannels`.
    private static func fetchSurfChannels(
        for media: PlayableMedia,
        sort: ContentSortOption,
        scope: LiveChannelScope?,
        in context: ModelContext
    ) -> [LiveStream] {
        guard case let .live(id) = media.contentRef else { return [] }
        var currentDescriptor = FetchDescriptor<LiveStream>(predicate: #Predicate { $0.id == id })
        currentDescriptor.fetchLimit = 1
        guard let current = try? context.fetch(currentDescriptor).first else { return [] }

        // Extract the owning playlist's UUID prefix from the stream id
        // (all stream ids are formatted "<playlistUUID>-live-<streamId>").
        let playlistPrefix = String(current.id.prefix(36)) + "-"

        if let scope, case .all = scope {
            var descriptor = FetchDescriptor<LiveStream>(
                predicate: #Predicate { $0.isHidden == false && $0.id.starts(with: playlistPrefix) },
                sortBy: sort.liveStreamDescriptors
            )
            descriptor.fetchLimit = 200
            return (try? context.fetch(descriptor)) ?? []
        }
        if let scope, case .favorites = scope {
            let descriptor = FetchDescriptor<LiveStream>(
                predicate: #Predicate { $0.isFavorite && $0.isHidden == false && $0.id.starts(with: playlistPrefix) },
                sortBy: [
                    SortDescriptor(\LiveStream.favoriteOrder),
                    SortDescriptor(\LiveStream.num),
                    SortDescriptor(\LiveStream.name)
                ]
            )
            return (try? context.fetch(descriptor)) ?? []
        }
        if let scope, case .recentlyWatched = scope {
            var descriptor = FetchDescriptor<LiveStream>(
                predicate: #Predicate { $0.lastWatchedDate != nil && $0.isHidden == false && $0.id.starts(with: playlistPrefix) },
                sortBy: [SortDescriptor(\LiveStream.lastWatchedDate, order: .reverse)]
            )
            descriptor.fetchLimit = 50
            return (try? context.fetch(descriptor)) ?? []
        }

        // Default: surf within the same category (already playlist-scoped via categoryId prefix)
        guard let categoryId = current.categoryId else { return [] }
        let descriptor = FetchDescriptor<LiveStream>(
            predicate: #Predicate { $0.categoryId == categoryId },
            sortBy: sort.liveStreamDescriptors
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
