import Foundation
import SwiftData
import Testing
@testable import Apex

@Suite struct HomeMediaItemProgressTests {
    @Test func `series resume uses newest in-progress episode without relationship`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)

        let series = Series(id: "pl-series-7", seriesId: 7, name: "Test Show")
        context.insert(series)

        let older = Episode(
            id: "pl-series-7-episode-1",
            episodeId: "1",
            title: "Pilot",
            containerExtension: "mp4",
            seasonNum: 1,
            episodeNum: 1
        )
        older.durationSecs = 1000
        older.watchProgress = 200
        older.lastWatchedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let newer = Episode(
            id: "pl-series-7-episode-2",
            episodeId: "2",
            title: "Next",
            containerExtension: "mp4",
            seasonNum: 1,
            episodeNum: 2
        )
        newer.durationSecs = 2000
        newer.watchProgress = 500
        newer.lastWatchedDate = Date(timeIntervalSince1970: 1_700_100_000)

        context.insert(older)
        context.insert(newer)
        try context.save()

        #expect(series.episodes.isEmpty, "Progress must not depend on Series.episodes being populated")

        let fraction = HomeMediaItem.seriesResumeFraction(seriesId: series.id, in: context)
        #expect(fraction == 0.25)
    }

    @Test func `series resume ignores watched and zero-progress episodes`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)

        let series = Series(id: "pl-series-8", seriesId: 8, name: "Done Show")
        context.insert(series)

        let watched = Episode(
            id: "pl-series-8-episode-1",
            episodeId: "1",
            title: "Done",
            containerExtension: "mp4",
            seasonNum: 1,
            episodeNum: 1
        )
        watched.durationSecs = 1000
        watched.watchProgress = 1000
        watched.isWatched = true
        watched.lastWatchedDate = Date()
        context.insert(watched)
        try context.save()

        #expect(HomeMediaItem.seriesResumeFraction(seriesId: series.id, in: context) == nil)
    }

    @Test func `movie resume fraction`() {
        let movie = Movie(id: "m1", streamId: 1, name: "Film", num: 1)
        movie.durationSecs = 100
        movie.watchProgress = 40
        #expect(HomeMediaItem.movieResumeFraction(movie) == 0.4)

        movie.isWatched = true
        #expect(HomeMediaItem.movieResumeFraction(movie) == nil)
    }
}
