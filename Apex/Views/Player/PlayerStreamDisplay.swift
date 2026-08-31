import Foundation

/// Merges server-reported stream metadata (media servers) with live decoder
/// stats (`PlayerVideoInfo`) for the player overlay captions and info badges.
enum PlayerStreamDisplay {
    static func caption(for media: PlayableMedia, videoInfo: PlayerVideoInfo?) -> String? {
        let parts = technicalParts(for: media, videoInfo: videoInfo)
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "  ·  ")
    }

    static func badges(for media: PlayableMedia, videoInfo: PlayerVideoInfo?) -> [String] {
        var badges: [String] = []
        if let method = media.streamContext?.methodBadge {
            badges.append(method)
        }
        if let quality = resolvedQualityTag(for: media, videoInfo: videoInfo), !quality.isEmpty {
            badges.append(quality)
        }
        if let codec = resolvedCodec(for: media, videoInfo: videoInfo) {
            badges.append(codec.uppercased())
        }
        return badges
    }

    static func technicalParts(for media: PlayableMedia, videoInfo: PlayerVideoInfo?) -> [String] {
        var parts: [String] = []
        if let quality = resolvedQualityTag(for: media, videoInfo: videoInfo), !quality.isEmpty {
            parts.append(quality)
        }
        if let codec = resolvedCodec(for: media, videoInfo: videoInfo) {
            parts.append(codec.uppercased())
        }
        if let fps = resolvedFPS(for: media, videoInfo: videoInfo), fps > 0 {
            let rounded = (fps * 100).rounded() / 100
            let text = rounded.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", rounded)
                : String(format: "%.2f", rounded)
            parts.append("\(text) fps")
        }
        if parts.isEmpty, let method = media.streamContext?.methodBadge {
            parts.append(method)
        }
        return parts
    }

    private static func resolvedQualityTag(for media: PlayableMedia, videoInfo: PlayerVideoInfo?) -> String? {
        if let videoInfo, !videoInfo.qualityTag.isEmpty { return videoInfo.qualityTag }
        if let ctx = media.streamContext, !ctx.qualityTag.isEmpty { return ctx.qualityTag }
        return nil
    }

    private static func resolvedCodec(for media: PlayableMedia, videoInfo: PlayerVideoInfo?) -> String? {
        if let codec = videoInfo?.codec, !codec.isEmpty { return codec }
        return media.streamContext?.displayVideoCodec
    }

    private static func resolvedFPS(for media: PlayableMedia, videoInfo: PlayerVideoInfo?) -> Double? {
        if let videoInfo, videoInfo.fps > 0 { return videoInfo.fps }
        if let fps = media.streamContext?.frameRate, fps > 0 { return fps }
        return nil
    }
}
