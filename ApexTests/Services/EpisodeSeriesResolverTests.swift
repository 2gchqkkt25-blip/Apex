import Foundation
import SwiftData
import Testing
@testable import Apex

@Suite struct EpisodeSeriesResolverTests {
    @Test func `parses series id from episode id`() {
        #expect(
            EpisodeSeriesResolver.seriesID(fromEpisodeID: "abc-series-42-episode-9001")
                == "abc-series-42"
        )
    }

    @Test func `returns nil for ids without episode marker`() {
        #expect(EpisodeSeriesResolver.seriesID(fromEpisodeID: "movie-123") == nil)
    }

    @Test func `links series from episode id when inverse is missing`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)

        let series = Series(id: "pl-series-7", seriesId: 7, name: "Test Show")
        context.insert(series)

        let episode = Episode(
            id: "pl-series-7-episode-99",
            episodeId: "99",
            title: "Pilot",
            containerExtension: "mp4",
            seasonNum: 1,
            episodeNum: 1
        )
        context.insert(episode)
        try context.save()

        #expect(episode.series == nil)

        let resolved = EpisodeSeriesResolver.series(for: episode, in: context)
        #expect(resolved?.id == "pl-series-7")
        #expect(episode.series?.id == "pl-series-7")
    }
}
