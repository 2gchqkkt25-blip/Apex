//
//  PlaylistDeletion.swift
//  Apex
//
//  Deleting a `Playlist` cascade-removes its `Category` rows (and, in turn, a
//  `Series`' episodes and a `Movie`/`Series`' cast, which cascade from their
//  parents). But `Movie`, `Series` and `LiveStream` are tied to a playlist only
//  by an `id` prefixed with the playlist's UUID — there is no SwiftData
//  relationship to cascade through. Left alone they orphan in the store forever:
//  they bloat storage (Settings then shows far more data than the active
//  playlist holds) and the content indexer keeps resolving titles whose playlist
//  no longer exists.
//
//  This removes that orphaned catalog content alongside the playlist. Run it on
//  the same context the deletion happens on so `@Query`-backed views refresh.
//

import Foundation
import OSLog
import SwiftData

/// `nonisolated` so it can run both on the main actor (the Settings deletion
/// buttons) and on a background `ModelContext` (legacy iCloud path). Cloud
/// reconcile no longer calls this for a still-present local playlist — a missing
/// mirror is re-published instead of treated as a remote delete.
nonisolated enum PlaylistDeletion {
    /// Deletes `playlist` and every catalog item it brought in. Categories,
    /// episodes and cast members cascade from their parents; movies, series and
    /// live streams are matched by their playlist-scoped id prefix and removed
    /// explicitly, and the now-orphaned EPG listings for the playlist's channels
    /// are pruned.
    static func delete(_ playlist: Playlist, in context: ModelContext) {
        let prefix = playlist.id.uuidString

        // `starts(with:)` rather than `localizedStandardContains`: the id is
        // `"<playlistUUID>-<kind>-<providerID>"`, so an anchored prefix match is
        // both exact and index-servable, where a locale-aware substring scan
        // forces a full table walk of every row it considers.
        deleteAll(matching: #Predicate<Movie> { $0.id.starts(with: prefix) }, in: context)
        deleteAll(matching: #Predicate<Series> { $0.id.starts(with: prefix) }, in: context)

        var removedChannelIDs = Set<String>()
        deleteAll(matching: #Predicate<LiveStream> { $0.id.starts(with: prefix) }, in: context) { stream in
            if let channelID = stream.epgChannelId { removedChannelIDs.insert(channelID) }
        }

        // Which of the removed channels does some *other* playlist still carry?
        //
        // This used to ask the inverse question — fetch every stream NOT in this
        // playlist — which on a 17K-channel library hydrated the entire
        // remaining table in one go, directly contrary to the scoping the rest
        // of this function is careful about. Only the removed playlist's own EPG
        // ids can possibly be orphaned, so scope the question to those and fault
        // just the one column being read.
        var survivingChannelIDs = Set<String>()
        if !removedChannelIDs.isEmpty {
            let candidates: [String?] = removedChannelIDs.map { $0 }
            var survivingDescriptor = FetchDescriptor<LiveStream>(
                predicate: #Predicate { stream in
                    !stream.id.starts(with: prefix) && candidates.contains(stream.epgChannelId)
                }
            )
            survivingDescriptor.propertiesToFetch = [\.epgChannelId]
            let surviving = (try? context.fetch(survivingDescriptor)) ?? []
            survivingChannelIDs = Set(surviving.compactMap(\.epgChannelId))
        }

        // Drop the playlist's auto-created EPG source so it isn't re-synced.
        EPGSourceReconciler.remove(playlistID: playlist.id, in: context)

        // Delete categories explicitly (and clear the inverse) before the playlist
        // itself. Relying solely on cascade during a background-context save that
        // merges into the UI context can hit `_InvalidFutureBackingData` while
        // SwiftData walks `Category.playlist` in `_propagateDelete`.
        let categories = Array(playlist.categories)
        for category in categories {
            category.playlist = nil
            context.delete(category)
        }
        playlist.categories = []
        context.delete(playlist)

        // Prune the guide listings for channels no surviving playlist carries.
        // Scoped by `channelId` (now indexed) so this seeks the orphaned rows
        // instead of hydrating the entire — potentially huge — guide table.
        let orphanedChannelIDs = Array(removedChannelIDs.subtracting(survivingChannelIDs))
        if !orphanedChannelIDs.isEmpty {
            deleteAll(
                matching: #Predicate<EPGListing> { orphanedChannelIDs.contains($0.channelId) },
                in: context
            )
        }

        Logger.sync.info("Deleted playlist \(prefix) and its orphaned catalog content")
    }

    /// How many rows to hydrate, delete and save at a time.
    private static let batchSize = 500

    /// Deletes every row matching `predicate` in bounded batches.
    ///
    /// Fetching the full match set at once meant a playlist with 20K titles or
    /// 17K channels hydrated all of them, and — because deletes stay pending in
    /// the context until a save — held every one of them until the caller saved
    /// at the very end. Saving per batch lets each batch's rows leave the
    /// context, which is what keeps peak memory flat regardless of library size.
    ///
    /// `observe` runs on each row before it is deleted, for callers that need to
    /// read a column off the rows on their way out.
    private static func deleteAll<T: PersistentModel>(
        matching predicate: Predicate<T>,
        in context: ModelContext,
        observe: (T) -> Void = { _ in }
    ) {
        while true {
            var descriptor = FetchDescriptor<T>(predicate: predicate)
            descriptor.fetchLimit = batchSize
            let batch = (try? context.fetch(descriptor)) ?? []
            guard !batch.isEmpty else { return }

            for model in batch {
                observe(model)
                context.delete(model)
            }
            // Bail rather than retry on a failed save: the same rows would match
            // the next fetch, and this loop would never terminate.
            do {
                try context.save()
            } catch {
                Logger.sync.error("Batched delete stopped — save failed: \(error.localizedDescription)")
                return
            }
            if batch.count < batchSize { return }
        }
    }
}
