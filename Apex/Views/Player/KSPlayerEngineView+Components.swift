//
//  KSPlayerEngineView+Components.swift
//  Apex
//
//  The invisible tap-catcher button style and the SwiftUI preview, split out of
//  KSPlayerEngineView to keep that file within the project's size limit.
//

import SwiftUI

#if os(tvOS)
    /// Draws only its (clear) label — no focus highlight, scale or background —
    /// so the full-screen tap-catcher stays invisible even while it holds focus
    /// with the controls hidden.
    struct KSInvisibleButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
        }
    }
#endif

private enum KSPlayerEngineViewPreviewData {
    static let sampleURL = URL(string: "https://example.com/stream.m3u8") ?? URL(fileURLWithPath: "/")
}

#Preview("Fallback") {
    KSPlayerEngineView(
        media: PlayableMedia(
            id: "preview",
            url: KSPlayerEngineViewPreviewData.sampleURL,
            title: "Sample Video",
            subtitle: nil,
            posterURL: nil,
            kind: .vod,
            startTime: 0,
            contentRef: .movie("preview")
        ),
        clock: PlaybackClock(),
        seekBridge: PlayerSeekBridge()
    )
    .preferredColorScheme(.dark)
}
