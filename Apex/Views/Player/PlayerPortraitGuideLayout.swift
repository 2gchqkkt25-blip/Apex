//
//  PlayerPortraitGuideLayout.swift
//  Apex
//
//  iPhone portrait + in-player Guide: pin the 16:9 video to the top so the
//  unused letterbox above the picture becomes extra Guide height below it.
//

import SwiftUI

enum PlayerPortraitGuideLayout {
    /// Compact Guide height when the video stays full-screen (landscape / macOS).
    static let compactGuideHeight: CGFloat = 280
    /// Live TV is almost always 16:9; used to reserve the video band in portrait.
    static let landscapeVideoAspect: CGFloat = 16 / 9

    static func isPortrait(_ size: CGSize) -> Bool {
        size.height > size.width + 1
    }

    /// Height of a width-fitted 16:9 frame in `size`.
    static func videoBandHeight(in size: CGSize) -> CGFloat {
        min(size.width / landscapeVideoAspect, size.height)
    }

    /// True when the video should sit at the top and the Guide should expand.
    static func pinsVideoToTop(guideOpen: Bool, canvas: CGSize, aspectFill: Bool = false) -> Bool {
        #if os(iOS)
            guard guideOpen, !aspectFill else { return false }
            return isPortrait(canvas)
        #else
            return false
        #endif
    }
}

#if !os(tvOS)
    /// Overlay column that either keeps the classic centered-video chrome or,
    /// in iPhone portrait with the Guide open, reserves the 16:9 band and lets
    /// the Guide fill everything under the picture.
    struct PlayerPortraitGuideChrome<TopBar: View, Transport: View, Guide: View, Bottom: View>: View {
        let isGuideOpen: Bool
        let isLive: Bool
        var aspectFill = false
        @ViewBuilder var topBar: TopBar
        @ViewBuilder var centerTransport: Transport
        @ViewBuilder var guide: Guide
        @ViewBuilder var bottomControls: Bottom

        var body: some View {
            GeometryReader { geo in
                let pinTop = PlayerPortraitGuideLayout.pinsVideoToTop(
                    guideOpen: isGuideOpen && isLive,
                    canvas: geo.size,
                    aspectFill: aspectFill
                )
                let videoBand = PlayerPortraitGuideLayout.videoBandHeight(in: geo.size)
                VStack(spacing: 0) {
                    if pinTop {
                        Color.clear
                            .frame(height: videoBand)
                            .overlay(alignment: .top) {
                                topBar.safeAreaPadding(.top)
                            }
                    } else {
                        topBar
                            .safeAreaPadding(.top)
                        Spacer(minLength: 0)
                        if !isGuideOpen {
                            centerTransport
                            Spacer(minLength: 0)
                        }
                    }
                    if isGuideOpen, isLive {
                        if pinTop {
                            guide
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            guide
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                                .frame(height: PlayerPortraitGuideLayout.compactGuideHeight)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    bottomControls
                        .safeAreaPadding(.bottom)
                }
            }
            .ignoresSafeArea()
        }
    }
#endif

extension View {
    /// Shrinks the video surface to a top-aligned 16:9 band while the in-player
    /// Guide is open in iPhone portrait. Other platforms keep a full-screen fill.
    func playerVideoPinnedToTopWhileGuideOpen(guideOpen: Bool, aspectFill: Bool = false) -> some View {
        modifier(PlayerVideoPortraitPin(guideOpen: guideOpen, aspectFill: aspectFill))
    }
}

private struct PlayerVideoPortraitPin: ViewModifier {
    let guideOpen: Bool
    let aspectFill: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
            GeometryReader { geo in
                let pinTop = PlayerPortraitGuideLayout.pinsVideoToTop(
                    guideOpen: guideOpen,
                    canvas: geo.size,
                    aspectFill: aspectFill
                )
                let band = PlayerPortraitGuideLayout.videoBandHeight(in: geo.size)
                content
                    .frame(width: geo.size.width, height: pinTop ? band : geo.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.22), value: guideOpen)
        #else
            content.ignoresSafeArea()
        #endif
    }
}
