//
//  TVHomeScreen.swift
//  Apex
//
//  The immersive tvOS home screen, modelled on the Apple TV app and Apple's
//  "Creating a tvOS media catalog app in SwiftUI" sample:
//
//  • The TMDB backdrop is a FIXED full-screen layer behind the scroll view
//    (horizontally paging between slides), so artwork always fills the screen.
//  • The scroll content opens with a "showcase" slot sized to the screen height
//    minus `TVHomeMetrics.rowPeek`, so the first row teases at the bottom edge.
//  • `TVHomeFoldBehavior` (a custom `ScrollTargetBehavior`, in
//    `TVHomeFold.swift`) snaps the fold in three stages: the first move down
//    parks the first row mid-screen with the hero's bottom strip still visible
//    (`.strip`), the next hides the hero entirely (`.rows`), and moving back
//    up restores the full hero.
//

#if os(tvOS)

    import SwiftUI

    // MARK: - Screen

    /// The immersive home: full-screen backdrop behind a single native vertical
    /// ScrollView. tvOS owns focus and scrolling; `TVHomeFoldBehavior` only
    /// adjusts where each focus-driven scroll comes to rest.
    struct TVHomeScreen<Rows: View>: View {
        let heroItems: [HeroItem]
        /// Called when the hero surface is selected; the owner navigates.
        let onSelectHero: (HeroItem) -> Void
        @ViewBuilder var rows: Rows

        @State private var controller = HomeHeroController()
        @State private var zone: TVHomeZone = .expanded
        @State private var containerHeight: CGFloat = 0

        private var showcaseHeight: CGFloat {
            max(containerHeight - TVHomeMetrics.rowPeek, 0)
        }

        private var belowFold: Bool {
            zone != .expanded
        }

        private var hasHero: Bool {
            !heroItems.isEmpty
        }

        var body: some View {
            ZStack {
                if hasHero {
                    TVHeroBackdrop(
                        controller: controller,
                        belowFold: belowFold,
                        height: containerHeight
                    )
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: TVHomeMetrics.rowSpacing) {
                        if hasHero {
                            TVHeroShowcase(controller: controller, onSelect: onSelectHero)
                        }
                        rows
                    }
                    .padding(.top, hasHero ? 0 : 60)
                    .padding(.bottom, 60)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .scrollTargetBehavior(TVHomeFoldBehavior(
                    zone: zone,
                    showcaseHeight: hasHero ? showcaseHeight : 0
                ))
                .onScrollGeometryChange(for: TVHomeZone.self) { geometry in
                    TVHomeZone(
                        offset: geometry.contentOffset.y + geometry.contentInsets.top,
                        showcaseHeight: hasHero ? showcaseHeight : 0
                    )
                } action: { _, newZone in
                    guard newZone != zone else { return }
                    withAnimation(.easeInOut(duration: 0.5)) { zone = newZone }
                }
            }
            .ignoresSafeArea(edges: .vertical)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                containerHeight = height
            }
            .onChange(of: zone) { _, newZone in
                controller.isPaused = newZone != .expanded
            }
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
        }
    }

    // MARK: - Backdrop layer

    /// The fixed full-screen artwork behind the scroll content. Pages
    /// horizontally on slide changes and frosts/dims once the user scrolls below
    /// the fold — Apple's material-masked-by-gradient treatment from the media
    /// catalog sample, plus a bottom scrim that keeps the hero copy legible.
    private struct TVHeroBackdrop: View {
        @Bindable var controller: HomeHeroController
        let belowFold: Bool
        let height: CGFloat

        var body: some View {
            ZStack {
                Color.black

                if height > 0 {
                    HomeHeroArtworkPager(
                        controller: controller,
                        height: height,
                        isInteractive: false
                    )
                }
            }
            .overlay {
                Rectangle()
                    .fill(GlassFallback.regular)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0.2),
                                .init(color: .black.opacity(belowFold ? 1 : 0.3), location: 0.375),
                                .init(color: .black.opacity(belowFold ? 1 : 0), location: 0.5)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    }
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.3),
                        .init(color: .black.opacity(0.45), location: 0.62),
                        .init(color: .black.opacity(0.85), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay {
                Color.black.opacity(belowFold ? 0.45 : 0)
            }
            .compositingGroup()
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    // MARK: - Showcase

    /// The focusable hero surface at the top of the scroll content: title logo,
    /// overview, Details affordance and the slide dots, bottom-aligned inside a
    /// slot that fills the screen minus the first-row peek. Selecting reports
    /// the hero via `onSelect` (navigation happens in `HomeView`); left/right
    /// pages the carousel.
    private struct TVHeroShowcase: View {
        @Bindable var controller: HomeHeroController
        let onSelect: (HeroItem) -> Void

        @FocusState private var heroFocused: Bool

        var body: some View {
            ZStack(alignment: .bottomLeading) {
                if let hero = controller.displayedHero {
                    heroContent(for: hero)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .containerRelativeFrame(.vertical, alignment: .topLeading) { length, _ in
                max(length - TVHomeMetrics.rowPeek, 0)
            }
            .focusSection()
            .task(id: controller.items.map(\.id)) {
                await runAutoAdvance()
            }
        }

        private func heroContent(for hero: HeroItem) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                info(for: hero)
                    .opacity(controller.infoOpacity)

                TVHeroPageDots(controller: controller)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 36)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func info(for hero: HeroItem) -> some View {
            VStack(alignment: .leading, spacing: 14) {
                TitleLogo(
                    url: hero.logoURL,
                    title: hero.title,
                    maxWidth: 500,
                    maxHeight: 130
                ) {
                    Text(hero.title)
                        .font(.system(size: 56, weight: .bold))
                        .lineLimit(2)
                        .shadow(radius: 6)
                }
                .id(hero.id)
                .frame(height: 130, alignment: .bottomLeading)

                Text(hero.overview)
                    .font(.callout)
                    .lineLimit(3, reservesSpace: true)
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(radius: 4)
                    .frame(maxWidth: 640, alignment: .leading)

                HStack {
                    Button {
                        onSelect(hero)
                    } label: {
                        detailsPill
                    }
                    .buttonStyle(TVHeroSurfaceButtonStyle())
                    .focused($heroFocused)
                    .onMoveCommand { direction in
                        switch direction {
                        case .left: Task { controller.retreat() }
                        case .right: Task { controller.advance() }
                        default: break
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
                .padding(.top, 10)
            }
            .foregroundStyle(.white)
        }

        private var detailsPill: some View {
            Label("Details", systemImage: "info.circle")
                .fontWeight(.semibold)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(
                    heroFocused
                        ? AnyShapeStyle(.white)
                        : GlassFallback.thin,
                    in: Capsule()
                )
                .foregroundStyle(heroFocused ? .black : .white)
                .scaleEffect(heroFocused ? 1.04 : 1.0)
                .animation(.easeOut(duration: 0.18), value: heroFocused)
        }

        private func runAutoAdvance() async {
            guard controller.items.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                if Task.isCancelled { return }
                if controller.tickAutoAdvance() {
                    controller.advance()
                }
            }
        }
    }

    /// Renders only the page dots, so the controller's 20 Hz `progress` ticks
    /// re-render this leaf and nothing else.
    private struct TVHeroPageDots: View {
        let controller: HomeHeroController

        var body: some View {
            if controller.items.count > 1 {
                HeroPageIndicator(
                    count: controller.items.count,
                    activeIndex: controller.currentIndex,
                    progress: controller.progress
                )
            }
        }
    }

    /// A focus-neutral button style for the full-hero surface: it renders only
    /// the label, so tvOS adds no automatic focus highlight (which would wash
    /// the entire hero white). The `detailsPill` reflects focus instead.
    private struct TVHeroSurfaceButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.85 : 1)
        }
    }

    // MARK: - Preview

    #Preview("Immersive Home") {
        let items = [
            HeroItem.movie(
                Movie(id: "preview-hero-1", streamId: 1, name: "The Matrix"),
                backdropURL: URL(string: "https://image.tmdb.org/t/p/w1280/fNG7i7RqM1T0sP1vQmRIqRnW.jpg"),
                overview: "A computer hacker learns about the true nature of reality."
            ),
            HeroItem.movie(
                Movie(id: "preview-hero-2", streamId: 2, name: "Inception"),
                backdropURL: nil,
                overview: "A thief who steals corporate secrets through dream-sharing technology."
            )
        ]
        NavigationStack {
            TVHomeScreen(
                heroItems: items,
                onSelectHero: { _ in },
                rows: {
                    Text("Rows go here")
                        .padding(.horizontal)
                }
            )
        }
    }

#endif
