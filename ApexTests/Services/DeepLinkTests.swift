import Foundation
@testable import Apex
import Testing

struct DeepLinkTests {
    @Test func `parses movie link`() throws {
        let url = try #require(URL(string: "apex://movie/603"))
        #expect(DeepLink(url: url) == .movie(tmdbId: 603, play: false))
    }

    @Test func `parses series link`() throws {
        let url = try #require(URL(string: "apex://series/1396"))
        #expect(DeepLink(url: url) == .series(tmdbId: 1396, play: false))
    }

    @Test func `scheme is case insensitive`() throws {
        let url = try #require(URL(string: "APEX://MOVIE/42"))
        #expect(DeepLink(url: url) == .movie(tmdbId: 42, play: false))
    }

    @Test func `tolerates a trailing slash`() throws {
        let url = try #require(URL(string: "apex://series/77/"))
        #expect(DeepLink(url: url) == .series(tmdbId: 77, play: false))
    }

    @Test func `rejects a foreign scheme`() throws {
        let url = try #require(URL(string: "https://movie/603"))
        #expect(DeepLink(url: url) == nil)
    }

    @Test func `rejects an unknown kind`() throws {
        let url = try #require(URL(string: "apex://episode/603"))
        #expect(DeepLink(url: url) == nil)
    }

    @Test func `rejects a non-numeric id`() throws {
        let url = try #require(URL(string: "apex://movie/not-a-number"))
        #expect(DeepLink(url: url) == nil)
    }

    @Test func `rejects a missing id`() throws {
        let url = try #require(URL(string: "apex://movie"))
        #expect(DeepLink(url: url) == nil)
    }
}
