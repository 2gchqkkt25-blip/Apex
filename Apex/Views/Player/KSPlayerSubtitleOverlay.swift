//
//  KSPlayerSubtitleOverlay.swift
//  Apex
//
//  Renders KSPlayer's `SubtitleModel` over the video surface. The stock
//  `KSVideoPlayerView` includes `VideoSubtitleView`, but Apex drives playback
//  through the lower-level `KSVideoPlayer` representable plus custom controls,
//  so this overlay is required for selected subtitles to actually appear.
//

import KSPlayer
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
struct KSPlayerSubtitleOverlay: View {
    @ObservedObject var model: SubtitleModel

    var body: some View {
        ZStack {
            ForEach(model.parts) { part in
                partView(part)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func partView(_ part: SubtitlePart) -> some View {
        VStack {
            if let image = part.image {
                Spacer()
                subtitleImage(image)
                    .padding()
            } else if let text = part.text {
                let position = part.textPosition ?? SubtitleModel.textPosition
                if position.verticalAlign == .bottom || position.verticalAlign == .center {
                    Spacer()
                }
                Text(AttributedString(text))
                    .font(Font(SubtitleModel.textFont))
                    .shadow(color: .black.opacity(0.9), radius: 1, x: 1, y: 1)
                    .foregroundStyle(SubtitleModel.textColor)
                    .italic(SubtitleModel.textItalic)
                    .background(SubtitleModel.textBackgroundColor)
                    .multilineTextAlignment(.center)
                    .alignmentGuide(position.horizontalAlign) { $0[.leading] }
                    .padding(position.edgeInsets)
                #if !os(tvOS)
                    .textSelection(.enabled)
                #endif
                if position.verticalAlign == .top || position.verticalAlign == .center {
                    Spacer()
                }
            } else {
                Text("")
            }
        }
    }

    @ViewBuilder
    private func subtitleImage(_ image: UIImage) -> some View {
        #if canImport(UIKit)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        #elseif canImport(AppKit)
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        #endif
    }
}
