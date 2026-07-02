//
//  HomeHeroCarousel.swift
//  Apex
//
//  A Netflix / Apple TV-style hero carousel for the top of the home screen on
//  iPhone and macOS. (iPad uses `HomeImmersiveHomeScreen`; tvOS uses
//  `TVHomeScreen`.) Features trending movies the user owns using wide TMDB
//  backdrop artwork, auto-advancing every few seconds while honouring manual
//  swipes.
//

import SwiftUI

struct HomeHeroCarousel: View {
    let items: [HeroItem]

    @State private var controller = HomeHeroController()

    /// Width below which the hero switches to the stacked, full-width layout.
    private let compactWidthThreshold: CGFloat = 600
    private let heroHeight: CGFloat = 800

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let isCompact = width < compactWidthThreshold

            ZStack(alignment: .bottomLeading) {
                HomeHeroArtworkPager(controller: controller, height: heroHeight)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.15), .black.opacity(0.85)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                if let hero = controller.displayedHero {
                    HeroInfo(hero: hero, isCompact: isCompact)
                        .opacity(controller.infoOpacity)
                }

                pageIndicator
                    .frame(maxWidth: .infinity, alignment: .center)

                #if os(macOS)
                    sliderButtons
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif
            }
            .frame(width: width, height: heroHeight)
            .clipped()
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.35), value: controller.currentItemID)
        }
        .frame(height: heroHeight)
        .onAppear {
            controller.configure(items: items)
            controller.onAppear()
        }
        .onChange(of: items) { _, newItems in
            controller.configure(items: newItems)
        }
        .onChange(of: controller.currentItemID) { _, _ in
            controller.onCurrentItemChanged()
        }
        .task(id: items.count) {
            await runAutoAdvance()
        }
    }

    @ViewBuilder
    private var pageIndicator: some View {
        if items.count > 1 {
            HeroPageIndicator(
                count: items.count,
                activeIndex: controller.currentIndex,
                progress: controller.progress
            )
            .padding(.bottom, 14)
        }
    }

    #if os(macOS)
        @ViewBuilder
        private var sliderButtons: some View {
            if items.count > 1 {
                HStack {
                    sliderButton(systemName: "chevron.compact.left", action: controller.retreat)
                    Spacer()
                    sliderButton(systemName: "chevron.compact.right", action: controller.advance)
                }
                .padding(.horizontal, 16)
            }
        }

        private func sliderButton(systemName: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 6)
                    .frame(width: 40, height: 60)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HeroSliderButtonStyle())
        }
    #endif

    private func runAutoAdvance() async {
        guard items.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return }
            if controller.tickAutoAdvance() {
                controller.advance()
            }
        }
    }
}

// MARK: - Preview

#Preview("Multiple Items") {
    let items = [
        HeroItem.movie(
            Movie(id: "preview-hero-1", streamId: 1, name: "The Matrix"),
            backdropURL: URL(string: "https://image.tmdb.org/t/p/w1280/fNG7i7RqM1T0sP1vQmRIqRnW.jpg"),
            overview: "A computer hacker learns about the true nature of reality."
        ),
        HeroItem.series(
            Series(id: "preview-series-1", seriesId: 1, name: "Breaking Bad", num: 1),
            backdropURL: nil,
            overview: "A high school chemistry teacher diagnosed with inoperable cancer."
        ),
        HeroItem.movie(
            Movie(id: "preview-hero-2", streamId: 2, name: "Inception"),
            backdropURL: nil,
            overview: "A thief who steals corporate secrets through dream-sharing technology."
        )
    ]
    HomeHeroCarousel(items: items)
}

#Preview("Single Item") {
    let items = [
        HeroItem.movie(
            Movie(id: "preview-hero-3", streamId: 3, name: "The Dark Knight"),
            backdropURL: nil,
            overview: "When the menace known as the Joker wreaks havoc on Gotham."
        )
    ]
    HomeHeroCarousel(items: items)
}

#Preview("Empty") {
    HomeHeroCarousel(items: [])
}

#if os(macOS)
    /// Translucent pill behind the carousel arrows that brightens on hover and
    /// dims on press — gives the pointer the feedback macOS users expect.
    private struct HeroSliderButtonStyle: ButtonStyle {
        @State private var isHovering = false

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background {
                    Capsule()
                        .fill(.black.opacity(isHovering ? 0.45 : 0.25))
                }
                .opacity(configuration.isPressed ? 0.6 : (isHovering ? 1 : 0.85))
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .onHover { isHovering = $0 }
                .animation(.easeInOut(duration: 0.15), value: isHovering)
                .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
        }
    }
#endif
