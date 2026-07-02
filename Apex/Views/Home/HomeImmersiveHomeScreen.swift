//
//  HomeImmersiveHomeScreen.swift
//  Apex
//
//  iPad home layout: a fixed full-screen TMDB backdrop that pages horizontally
//  behind the scroll content, matching the cinematic feel of the iPhone hero
//  while keeping rows readable over a dimmed layer.
//

#if os(iOS)

    import SwiftUI

    struct HomeImmersiveHomeScreen<Rows: View>: View {
        let heroItems: [HeroItem]
        let backgroundColor: Color
        @ViewBuilder var rows: Rows

        @State private var controller = HomeHeroController()

        private let heroHeight: CGFloat = 800
        private let compactWidthThreshold: CGFloat = 600

        private var hasHero: Bool {
            !heroItems.isEmpty
        }

        var body: some View {
            GeometryReader { proxy in
                let isCompact = proxy.size.width < compactWidthThreshold

                ZStack {
                    if hasHero {
                        HomeHeroArtworkPager(
                            controller: controller,
                            height: proxy.size.height,
                            isInteractive: false
                        )
                        .overlay {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.15), .black.opacity(0.85)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        }
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 28) {
                            if hasHero, let hero = controller.displayedHero {
                                ZStack(alignment: .bottomLeading) {
                                    Color.clear
                                    HeroInfo(hero: hero, isCompact: isCompact)
                                        .opacity(controller.infoOpacity)
                                    if heroItems.count > 1 {
                                        HeroPageIndicator(
                                            count: heroItems.count,
                                            activeIndex: controller.currentIndex,
                                            progress: controller.progress
                                        )
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.bottom, 14)
                                    }
                                }
                                .frame(height: heroHeight)
                            }
                            rows
                        }
                        .padding(.bottom)
                    }
                    .scrollIndicators(.hidden)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(backgroundColor)
            .onChange(of: heroItems) { _, items in
                controller.configure(items: items)
            }
            .onAppear {
                controller.configure(items: heroItems)
                controller.onAppear()
            }
            .onChange(of: controller.currentItemID) { _, _ in
                controller.onCurrentItemChanged()
            }
            .task(id: heroItems.count) {
                await runAutoAdvance()
            }
        }

        private func runAutoAdvance() async {
            guard heroItems.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                if Task.isCancelled { return }
                if controller.tickAutoAdvance() {
                    controller.advance()
                }
            }
        }
    }

#endif