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

    @Test func `authenticatedStreamURL leaves an external aio stream alone`() throws {
        let url = try #require(URL(string: "https://cdn.example/file.mkv"))
        let server = try #require(URL(string: "http://192.168.1.65:8095/jellyfin"))
        let out = MediaPlaybackResolver.authenticatedStreamURL(
            url,
            token: "secret",
            serverKind: .jellyfin,
            serverBase: server
        )
        #expect(out.absoluteString == url.absoluteString)
    }

    @Test func `versionChoices keeps each named source in order`() {
        let streams = [
            sampleVersion(id: "a", label: "Torrentio 1080p", url: "https://cdn.example/a.mkv"),
            sampleVersion(id: "a", label: "Torrentio 1080p", url: "https://cdn.example/a-hls.m3u8"),
            sampleVersion(id: "b", label: "MediaFusion 4K", url: "https://cdn.example/b.mkv")
        ]
        let choices = MediaPlaybackResolver.versionChoices(from: streams)
        #expect(choices.map(\.sourceID) == ["a", "b"])
        #expect(choices.map { MediaPlaybackResolver.versionTitle($0) } == ["Torrentio 1080p", "MediaFusion 4K"])
    }

    @Test func `swat matches a punctuated title`() {
        #expect(ContentIndexText.matchKey(for: "S.W.A.T.") == ContentIndexText.matchKey(for: "SWAT"))
        #expect(ContentIndexText.matchKey(for: "Toy Story 5") != ContentIndexText.matchKey(for: "Toy Story"))
        let needles = ContentIndexText.searchNeedles(for: "swat")
        #expect(needles.contains("swat"))
        #expect(needles.contains("s.w.a.t"))
    }

    @Test func `packed aio item id yields the tmdb id`() {
        let ids = JellyfinClient.packedProviderIDs(itemID: "a11201000000000226ffffffffff000000")
        #expect(ids.tmdb == 550)
        #expect(ids.imdb == nil)
    }

    @Test func `preferred language sorts a matching version first`() {
        let streams = [
            sampleVersion(id: "es", label: "Torrentio 1080p Spanish", url: "https://cdn.example/es.mkv"),
            sampleVersion(id: "en", label: "MediaFusion 1080p", url: "https://cdn.example/en.mkv", audioLabel: "eng English")
        ]
        let ordered = MediaServerAudioLanguage.english.preferring(streams)
        #expect(ordered.map(\.sourceID) == ["en", "es"])
        #expect(PreferredAudioTrack.index(
            matching: "en",
            labels: ["Spanish", "English"],
            hints: []
        ) == 1)
        #expect(PreferredAudioTrack.index(
            matching: "en",
            labels: ["Audio 1", "Audio 2"],
            hints: [MediaServerAudioHint(index: 1, label: "eng")]
        ) == 1)
        #expect(PreferredAudioTrack.index(
            matching: "en",
            labels: ["Português AAC", "eng"],
            hints: []
        ) == 1)
        #expect(MediaServerAudioLanguage.portuguese.matches("Português"))
        #expect(PreferredAudioTrack.decision(
            matching: "en",
            labels: ["aac"],
            hints: []
        ) == .wait)
    }

    @Test func `version detail lists language quality and size`() {
        let stream = sampleVersion(
            id: "en",
            label: "Torrentio",
            url: "https://cdn.example/en.mkv",
            meta: StreamVersionMeta(
                languages: ["English"],
                resolution: "1080p",
                byteSize: 2_500_000_000,
                addon: "Torrentio",
                filename: "Toy.Story.5.2026.1080p.mkv"
            )
        )
        let detail = MediaPlaybackResolver.versionDetail(stream)
        #expect(detail.contains("English"))
        #expect(detail.contains("1080p"))
        #expect(detail.contains("GB"))
        #expect(detail.contains("Torrentio"))
        #expect(detail.contains("Toy.Story.5"))
        let portuguese = sampleVersion(
            id: "pt",
            label: "MediaFusion",
            url: "https://cdn.example/pt.mkv",
            meta: StreamVersionMeta(languages: ["Portuguese"])
        )
        let ordered = MediaServerAudioLanguage.english.preferring([portuguese, stream])
        #expect(ordered.map(\.sourceID) == ["en", "pt"])
    }

    @Test func `versionChoices ignores a single jellyfin file`() {
        let streams = [
            sampleVersion(id: "only", label: nil, url: "http://jellyfin.local/Videos/1/stream.mkv"),
            sampleVersion(id: "only", label: nil, url: "http://jellyfin.local/Videos/1/master.m3u8")
        ]
        #expect(MediaPlaybackResolver.versionChoices(from: streams).isEmpty)
    }

    private func sampleVersion(
        id: String,
        label: String?,
        url: String,
        audioLabel: String? = nil,
        meta: StreamVersionMeta = StreamVersionMeta()
    ) -> MediaServerStreamInfo {
        MediaServerStreamInfo(
            url: URL(string: url)!,
            method: .directPlay,
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "aac",
            width: 1920,
            height: 1080,
            frameRate: 24,
            videoBitrate: 8_000,
            label: label,
            sourceID: id,
            audioTracks: audioLabel.map { [MediaServerAudioHint(index: 0, label: $0)] } ?? [],
            meta: meta
        )
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
