import Foundation
@testable import Apex
import SwiftData
import Testing

struct SeriesResumeTests {
    @Test func `stable key strips playlist uuid`() {
        let playlist = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let id = "\(playlist.uuidString)-series-42-episode-7"
        #expect(ContentIdentity.stableKey(for: id) == "series-42-episode-7")
        #expect(ContentIdentity.stableKey(for: "not-a-uuid-id") == nil)
    }

    @Test func `resume prefers most recently watched in-progress episode`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let playlist = Playlist(name: "P", serverURL: "http://x", username: "u", password: "p")
        context.insert(playlist)
        let series = Series(id: "\(playlist.id.uuidString)-series-1", seriesId: 1, name: "Show")
        context.insert(series)

        let older = Episode(
            id: "\(series.id)-episode-1",
            episodeId: "1",
            title: "S1E1",
            containerExtension: "mkv",
            seasonNum: 1,
            episodeNum: 1,
            series: series
        )
        older.watchProgress = 100
        older.lastWatchedDate = Date(timeIntervalSince1970: 1_700_000_000)
        series.episodes.append(older)
        context.insert(older)

        let newer = Episode(
            id: "\(series.id)-episode-2",
            episodeId: "2",
            title: "S2E1",
            containerExtension: "mkv",
            seasonNum: 2,
            episodeNum: 1,
            series: series
        )
        newer.watchProgress = 200
        newer.lastWatchedDate = Date(timeIntervalSince1970: 1_700_100_000)
        series.episodes.append(newer)
        context.insert(newer)
        try context.save()

        #expect(SeriesResume.episode(in: series)?.id == newer.id)
    }

    @Test func `resume advances past a completed recent episode`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let playlist = Playlist(name: "P", serverURL: "http://x", username: "u", password: "p")
        context.insert(playlist)
        let series = Series(id: "\(playlist.id.uuidString)-series-1", seriesId: 1, name: "Show")
        context.insert(series)

        let first = Episode(
            id: "\(series.id)-episode-1",
            episodeId: "1",
            title: "S1E1",
            containerExtension: "mkv",
            seasonNum: 1,
            episodeNum: 1,
            series: series
        )
        first.setWatched(true)
        first.lastWatchedDate = Date()
        series.episodes.append(first)
        context.insert(first)

        let second = Episode(
            id: "\(series.id)-episode-2",
            episodeId: "2",
            title: "S1E2",
            containerExtension: "mkv",
            seasonNum: 1,
            episodeNum: 2,
            series: series
        )
        series.episodes.append(second)
        context.insert(second)
        try context.save()

        #expect(SeriesResume.episode(in: series)?.id == second.id)
    }
}

struct DeepLinkPlayTests {
    @Test func `parses series play query`() throws {
        let url = try #require(URL(string: "apex://series/1396?play=1"))
        #expect(DeepLink(url: url) == .series(tmdbId: 1396, play: true))
    }

    @Test func `display link does not autoplay`() throws {
        let url = try #require(URL(string: "apex://series/1396"))
        #expect(DeepLink(url: url) == .series(tmdbId: 1396, play: false))
    }
}
