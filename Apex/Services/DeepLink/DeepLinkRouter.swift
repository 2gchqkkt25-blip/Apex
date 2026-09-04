//
//  DeepLinkRouter.swift
//  Apex
//

import SwiftUI

/// Shared navigation state a deep link drives: the selected tab and the Movies/
/// Series navigation stacks. `MainTabView` owns it and injects it into the
/// environment; `MoviesView` and `SeriesView` bind their `NavigationStack` to the
/// matching path so an `onOpenURL` push lands in the right tab.
@MainActor
@Observable
final class DeepLinkRouter {
    var selectedTab: AppTab = .home
    var moviesPath = NavigationPath()
    var seriesPath = NavigationPath()
}

/// Holds a `@Bindable` to `DeepLinkRouter` so Movies/Series can pass a stable
/// `Binding<NavigationPath>` into `NavigationStack`. A computed
/// `Binding(get:set:)` rebuilt on every render does not participate in
/// Observation on tvOS, so poster `NavigationLink`s never push.
struct DeepLinkNavigationStack<Content: View>: View {
    @Bindable var router: DeepLinkRouter
    var stack: Stack
    @ViewBuilder var content: (Binding<NavigationPath>) -> Content

    enum Stack {
        case movies
        case series
    }

    var body: some View {
        switch stack {
        case .movies: content($router.moviesPath)
        case .series: content($router.seriesPath)
        }
    }
}
