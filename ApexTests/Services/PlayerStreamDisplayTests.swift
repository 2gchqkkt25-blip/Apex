import Foundation
@testable import Apex
import Testing

struct PlayerStreamDisplayTests {
    @Test func mediaServerCaptionUsesServerMetadataBeforeDecoderStats() throws {
        let media = try PlayableMedia(
            id: "movie-ms",
            url: #require(URL(string: "http://127.0.0.1/video.mp4")),
            title: "Test",
            subtitle: nil,
            posterURL: nil,
            kind: .vod,
            startTime: 0,
            contentRef: .movie("m-1"),
            streamContext: MediaServerStreamContext(from: MediaServerStreamInfo(
                url: #require(URL(string: "http://127.0.0.1/video.mp4")),
                method: .directPlay,
                container: "mkv",
                videoCodec: "hevc",
                audioCodec: "aac",
                width: 3840,
                height: 2160,
                frameRate: 23.976,
                videoBitrate: 20_000_000
            ))
        )

        let caption = PlayerStreamDisplay.caption(for: media, videoInfo: nil)
        #expect(caption?.contains("4K") == true)
        #expect(caption?.contains("HEVC") == true)
        #expect(caption?.contains("23.98 fps") == true)
    }

    @Test func runtimeVideoInfoOverridesServerCodec() throws {
        let media = try PlayableMedia(
            id: "movie-ms",
            url: #require(URL(string: "http://127.0.0.1/video.mp4")),
            title: "Test",
            subtitle: nil,
            posterURL: nil,
            kind: .vod,
            startTime: 0,
            contentRef: .movie("m-1"),
            streamContext: MediaServerStreamContext(from: MediaServerStreamInfo(
                url: #require(URL(string: "http://127.0.0.1/video.mp4")),
                method: .transcode,
                container: "m3u8",
                videoCodec: "h264",
                audioCodec: "aac",
                width: 1920,
                height: 1080,
                frameRate: 24,
                videoBitrate: nil
            ))
        )

        let runtime = PlayerVideoInfo(width: 1920, height: 1080, fps: 23.976, codec: "HEVC")
        let caption = PlayerStreamDisplay.caption(for: media, videoInfo: runtime)
        #expect(caption?.contains("HEVC") == true)
        #expect(caption?.contains("H264") == false)

        let badges = PlayerStreamDisplay.badges(for: media, videoInfo: runtime)
        #expect(badges.contains("Transcode"))
        #expect(badges.contains("1080p"))
    }
}
