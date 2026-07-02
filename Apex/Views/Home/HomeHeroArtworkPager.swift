//
//  HomeHeroArtworkPager.swift
//  Apex
//
//  Horizontally paging TMDB backdrop artwork for the home hero. Can fill a
//  fixed full-screen layer (iPad/tvOS immersive) or sit inside the inline
//  carousel on iPhone and macOS.
//

import SwiftUI

struct HomeHeroArtworkPager: View {
    @Bindable var controller: HomeHeroController
    var height: CGFloat
    /// When false the pager is driven only by auto-advance / remote paging.
    var isInteractive: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(controller.slots) { slot in
                        HeroBackdropImage(url: slot.item.imageURL)
                            .frame(width: width, height: height)
                            .id(slot.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $controller.currentID)
            .scrollIndicators(.hidden)
            .scrollDisabled(!isInteractive)
            .onScrollPhaseChange { _, newPhase, _ in
                controller.onScrollPhaseChange(newPhase)
            }
        }
        .frame(height: height)
    }
}

/// Wide hero backdrop image used by the carousel and immersive home layouts.
struct HeroBackdropImage: View {
    let url: URL?

    var body: some View {
        GeometryReader { geo in
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.25))
                        .overlay { ProgressView() }
                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                case .failure:
                    Rectangle()
                        .fill(Color.gray.opacity(0.25))
                        .overlay {
                            Image(systemName: "film")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
