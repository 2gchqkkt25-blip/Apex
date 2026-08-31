import Foundation
@testable import Apex
import Testing

struct MediaPlaybackResolverTests {
    private func sampleStreams(directContainer: String = "mkv") -> [MediaServerStreamInfo] {
        let direct = URL(string: "http://192.168.1.1:32400/library/parts/1/file.\(directContainer)?token=x")!
        let hls = URL(string: "http://192.168.1.1:32400/video/:/transcode/universal/start.m3u8?token=x")!
        return [
            MediaServerStreamInfo(
                url: direct,
                method: .directPlay,
                container: directContainer,
                videoCodec: "hevc",
                audioCodec: "aac",
                width: 1920,
                height: 1080,
                frameRate: 24,
                videoBitrate: 8_000
            ),
            MediaServerStreamInfo(
                url: hls,
                method: .transcode,
                container: "m3u8",
                videoCodec: "hevc",
                audioCodec: "aac",
                width: 1920,
                height: 1080,
                frameRate: 24,
                videoBitrate: 8_000
            )
        ]
    }

    @Test func `jellyfin prefers hls transcode`() {
        let picked = MediaPlaybackResolver.pickBestStream(from: sampleStreams(), serverKind: .jellyfin)
        #expect(picked?.method == .transcode)
        #expect(picked?.container == "m3u8")
    }

    #if os(tvOS)
    @Test func `plex prefers hls transcode for mkv on tvOS`() {
        let picked = MediaPlaybackResolver.pickBestStream(
            from: sampleStreams(directContainer: "mkv"),
            serverKind: .plex,
            preferDirectPlay: false
        )
        #expect(picked?.method == .transcode)
        #expect(picked?.container == "m3u8")
        let forced = MediaPlaybackResolver.pickBestStream(
            from: sampleStreams(directContainer: "mkv"),
            serverKind: .plex,
            preferDirectPlay: true
        )
        #expect(forced?.method == .directPlay)
    }

    @Test func `plex direct plays mp4 on tvOS`() {
        let picked = MediaPlaybackResolver.pickBestStream(from: sampleStreams(directContainer: "mp4"), serverKind: .plex)
        #expect(picked?.method == .directPlay)
    }
    #endif

    @Test func `pickBestStream prefers direct play when forced`() {
        let picked = MediaPlaybackResolver.pickBestStream(
            from: sampleStreams(directContainer: "mkv"),
            serverKind: .plex,
            preferDirectPlay: true
        )
        #expect(picked?.method == .directPlay)
    }

    @Test func `authenticatedStreamURL skips api_key for plex token urls`() throws {
        let url = try #require(URL(string: "http://192.168.1.1:32400/video/:/transcode/universal/start.m3u8?X-Plex-Token=abc"))
        let out = MediaPlaybackResolver.authenticatedStreamURL(url, token: "abc", serverKind: .plex)
        #expect(out.absoluteString.contains("X-Plex-Token=abc"))
        #expect(!out.absoluteString.contains("api_key="))
    }

    @Test func `authenticatedStreamURL adds api_key for jellyfin urls`() throws {
        let url = try #require(URL(string: "http://jellyfin.local/Videos/abc/stream"))
        let out = MediaPlaybackResolver.authenticatedStreamURL(url, token: "secret", serverKind: .jellyfin)
        #expect(out.absoluteString.contains("api_key=secret"))
    }

    @Test func `plex constrained transcode uses fixed quality contract`() {
        let items = PlexClient.constrainedTranscodeQualityQueryItems
        let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(query["videoQuality"] == "100")
        #expect(query["videoResolution"] == "1920x1080")
        #expect(query["maxVideoBitrate"] == "12000")
        #expect(query["videoBitrate"] == nil)
        #expect(query["peakBitrate"] == nil)
        #expect(query["autoAdjustQuality"] == nil)
    }
}
