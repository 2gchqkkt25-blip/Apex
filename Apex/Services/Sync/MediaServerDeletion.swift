//
//  MediaServerDeletion.swift
//  Apex
//
//  Removes a media server and all catalog rows scoped to its UUID prefix.
//  Used from settings UI and iCloud reconcile deletion paths.
//

import Foundation
import SwiftData

nonisolated enum MediaServerDeletion {
    static func delete(_ server: MediaServer, in context: ModelContext) {
        let serverUUID = server.id
        purgeCatalog(serverUUID: serverUUID, container: context.container)
        context.delete(server)
        try? context.save()
    }

    static func purgeCatalog(serverUUID: UUID, container: ModelContainer) {
        let moviePrefix = "\(serverUUID.uuidString)-movie-"
        let seriesPrefix = "\(serverUUID.uuidString)-series-"
        let episodePrefix = "\(serverUUID.uuidString)-episode-"
        purgeMovies(prefix: moviePrefix, container: container)
        purgeSeries(prefix: seriesPrefix, container: container)
        purgeEpisodes(prefix: episodePrefix, container: container)
    }

    private static func purgeMovies(prefix: String, container: ModelContainer) {
        purgeBatch(
            container: container,
            fetch: { ctx, offset, limit in
                var descriptor = FetchDescriptor<Movie>(
                    predicate: #Predicate { $0.id.starts(with: prefix) },
                    sortBy: [SortDescriptor(\.id)]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit
                return (try? ctx.fetch(descriptor)) ?? []
            },
            delete: { ctx, row in ctx.delete(row) }
        )
    }

    private static func purgeSeries(prefix: String, container: ModelContainer) {
        purgeBatch(
            container: container,
            fetch: { ctx, offset, limit in
                var descriptor = FetchDescriptor<Series>(
                    predicate: #Predicate { $0.id.starts(with: prefix) },
                    sortBy: [SortDescriptor(\.id)]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit
                return (try? ctx.fetch(descriptor)) ?? []
            },
            delete: { ctx, row in ctx.delete(row) }
        )
    }

    private static func purgeEpisodes(prefix: String, container: ModelContainer) {
        purgeBatch(
            container: container,
            fetch: { ctx, offset, limit in
                var descriptor = FetchDescriptor<Episode>(
                    predicate: #Predicate { $0.id.starts(with: prefix) },
                    sortBy: [SortDescriptor(\.id)]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit
                return (try? ctx.fetch(descriptor)) ?? []
            },
            delete: { ctx, row in ctx.delete(row) }
        )
    }

    private static func purgeBatch<T>(
        container: ModelContainer,
        fetch: (ModelContext, Int, Int) -> [T],
        delete: (ModelContext, T) -> Void
    ) {
        let batchSize = MediaServerCatalogLimits.catalogBatchSize
        var offset = 0
        while true {
            let ctx = ModelContext(container)
            let batch = fetch(ctx, offset, batchSize)
            guard !batch.isEmpty else { break }
            for row in batch {
                delete(ctx, row)
            }
            try? ctx.save()
            offset += batch.count
            if batch.count < batchSize { break }
        }
    }
}
