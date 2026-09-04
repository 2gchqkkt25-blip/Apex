import Foundation
import SwiftData
import Testing
@testable import Apex

struct PlaybackSeekTests {
    @Test func `skip forward uses current plus delta`() {
        #expect(PlaybackSeek.target(current: 40, duration: 120, delta: 15) == 55)
    }

    @Test func `skip back does not go below zero`() {
        #expect(PlaybackSeek.target(current: 4, duration: 120, delta: -15) == 0)
    }

    @Test func `unknown duration does not clamp skip to zero`() {
        #expect(PlaybackSeek.target(current: 40, duration: 0, delta: 15) == 55)
        #expect(PlaybackSeek.target(current: 40, duration: .nan, delta: 15) == 55)
    }

    @Test func `known duration clamps skip to the end`() {
        #expect(PlaybackSeek.target(current: 110, duration: 120, delta: 15) == 120)
    }
}

@Suite
struct RecentlyWatchedEvidenceTests {
    @Test func `movie without playback does not qualify`() {
        let movie = Movie(id: "p-movie-1", streamId: 1, name: "Film", num: 1)
        movie.lastWatchedDate = Date()
        movie.watchProgress = 1
        #expect(RecentlyWatchedEvidence.movieQualifies(movie) == false)
    }

    @Test func `movie with real progress qualifies`() {
        let movie = Movie(id: "p-movie-1", streamId: 1, name: "Film", num: 1)
        movie.lastWatchedDate = Date()
        movie.watchProgress = 30
        #expect(RecentlyWatchedEvidence.movieQualifies(movie))
    }

    @Test func `series with no episode playback does not qualify`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let series = Series(id: "pl-series-7", seriesId: 7, name: "Show")
        series.lastWatchedDate = Date()
        context.insert(series)
        let episode = Episode(
            id: "pl-series-7-episode-1",
            episodeId: "1",
            title: "Pilot",
            containerExtension: "mp4",
            seasonNum: 1,
            episodeNum: 1
        )
        episode.watchProgress = 1
        context.insert(episode)
        try context.save()
        #expect(RecentlyWatchedEvidence.seriesQualifies(id: series.id, in: context) == false)
    }

    @Test func `series with watched episode qualifies`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let series = Series(id: "pl-series-7", seriesId: 7, name: "Show")
        series.lastWatchedDate = Date()
        context.insert(series)
        let episode = Episode(
            id: "pl-series-7-episode-1",
            episodeId: "1",
            title: "Pilot",
            containerExtension: "mp4",
            seasonNum: 1,
            episodeNum: 1
        )
        episode.watchProgress = 40
        context.insert(episode)
        try context.save()
        #expect(RecentlyWatchedEvidence.seriesQualifies(id: series.id, in: context))
    }
}
