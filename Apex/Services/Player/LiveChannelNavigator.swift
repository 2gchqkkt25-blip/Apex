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
    static func adjacentMedia(
        for media: PlayableMedia,
        offset: Int,
        sort: ContentSortOption,
        scope: LiveChannelScope? = nil,
        in context: ModelContext
    ) -> PlayableMedia? {
        guard case let .live(id) = media.contentRef else { return nil }
        var currentDescriptor = FetchDescriptor<LiveStream>(predicate: #Predicate { $0.id == id })
        currentDescriptor.fetchLimit = 1
        guard let current = try? context.fetch(currentDescriptor).first else { return nil }

        let streams: [LiveStream]

        if let scope, case .all = scope {
            // Surf within all channels
            var descriptor = FetchDescriptor<LiveStream>(
                predicate: #Predicate { $0.isHidden == false },
                sortBy: sort.liveStreamDescriptors
            )
            descriptor.fetchLimit = 200
            streams = (try? context.fetch(descriptor)) ?? []
        } else if let scope, case .favorites = scope {
            // Surf within favorites only
            let descriptor = FetchDescriptor<LiveStream>(
                predicate: #Predicate { $0.isFavorite && $0.isHidden == false },
                sortBy: [
                    SortDescriptor(\LiveStream.favoriteOrder),
                    SortDescriptor(\LiveStream.num),
                    SortDescriptor(\LiveStream.name)
                ]
            )
            streams = (try? context.fetch(descriptor)) ?? []
        } else if let scope, case .recentlyWatched = scope {
            // Surf within recently watched
            var descriptor = FetchDescriptor<LiveStream>(
                predicate: #Predicate { $0.lastWatchedDate != nil && $0.isHidden == false },
                sortBy: [SortDescriptor(\LiveStream.lastWatchedDate, order: .reverse)]
            )
            descriptor.fetchLimit = 50
            streams = (try? context.fetch(descriptor)) ?? []
        } else {
            // Default: surf within the same category
            guard let categoryId = current.categoryId else { return nil }
            let descriptor = FetchDescriptor<LiveStream>(
                predicate: #Predicate { $0.categoryId == categoryId },
                sortBy: sort.liveStreamDescriptors
            )
            streams = (try? context.fetch(descriptor)) ?? []
        }

        guard streams.count > 1,
              let index = streams.firstIndex(where: { $0.id == current.id }) else { return nil }

        let target = streams[(index + offset + streams.count) % streams.count]
        guard let playlist = playlist(for: target, in: context) else { return nil }
        return PlayableMedia.from(stream: target, playlist: playlist)
    }
}
