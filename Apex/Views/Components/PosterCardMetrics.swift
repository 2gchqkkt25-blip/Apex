//
//  PosterCardMetrics.swift
//  Apex
//
//  Shared sizing for the poster cards used across the Home, Movies and Series
//  browse rows. tvOS needs noticeably larger cards, wider rail spacing and room
//  for the focus lift so titles and artwork never bleed into neighbouring cards
//  on the 10-foot UI; iOS keeps the compact phone-sized layout.
//

import SwiftUI

enum PosterCardMetrics {
    #if os(tvOS)
        static var posterWidth: CGFloat {
            DeviceMemoryTier.current.isConstrained ? 200 : 240
        }
        static var posterHeight: CGFloat {
            DeviceMemoryTier.current.isConstrained ? 300 : 360
        }
        static let cornerRadius: CGFloat = 12
        static let titleSpacing: CGFloat = 12
        static let titleFont: Font = .system(size: 24, weight: .medium)

        /// Gap between cards inside a horizontal browse rail.
        static let railSpacing: CGFloat = 48
        /// Vertical breathing room so the focus lift isn't clipped by the rail.
        static let railVerticalPadding: CGFloat = 28
        /// Height reserved for a rail: poster + two-line title + the focus lift.
        static var rowHeight: CGFloat {
            DeviceMemoryTier.current.isConstrained ? 400 : 470
        }
        /// Minimum item width for the "Show All" adaptive grid.
        static let gridMinimum: CGFloat = 240
        static let gridSpacing: CGFloat = 48
        /// Inset between a transparent channel logo and its card plate.
        static let liveLogoInset: CGFloat = 32
    #else
        static let posterWidth: CGFloat = 120
        static let posterHeight: CGFloat = 180
        static let cornerRadius: CGFloat = 8
        static let titleSpacing: CGFloat = 8
        static let titleFont: Font = .caption

        static let railSpacing: CGFloat = 16
        static let railVerticalPadding: CGFloat = 0
        static let rowHeight: CGFloat = 220
        static let gridMinimum: CGFloat = 100
        static let gridSpacing: CGFloat = 16
        static let liveLogoInset: CGFloat = 16
    #endif
}

extension View {
    /// Applies the focus-aware card button style on tvOS (scale + shadow on
    /// focus) and the plain style elsewhere, so browse cards lift cleanly
    /// without overlapping neighbours.
    @ViewBuilder
    func posterCardButtonStyle() -> some View {
        #if os(tvOS)
            buttonStyle(TVCardButtonStyle(focusScale: 1.14))
        #else
            buttonStyle(.plain)
        #endif
    }

    /// White ring around the poster that currently has focus. The scale lift
    /// alone is easy to miss while moving through a rail of similar artwork.
    @ViewBuilder
    func posterFocusRing() -> some View {
        #if os(tvOS)
            modifier(PosterFocusRing())
        #else
            self
        #endif
    }
}

#if os(tvOS)
    private struct PosterFocusRing: ViewModifier {
        @Environment(\.isFocused) private var isFocused

        func body(content: Content) -> some View {
            content
                .overlay {
                    RoundedRectangle(cornerRadius: PosterCardMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(.white, lineWidth: isFocused ? 6 : 0)
                }
                .animation(.easeOut(duration: 0.18), value: isFocused)
        }
    }
#endif

//
//  ApexContextMenu.swift
//  Apex
//
//  Secondary actions on posters, episodes, and rows. On macOS a plain button
//  consumes the right-click before SwiftUI's context menu can open, so the
//  poster itself opens the menu and lets a normal click through.
//

import SwiftUI

struct ApexContextAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var isDestructive = false
    var isDivider = false
    var isEnabled = true
    var perform: () -> Void = {}

    static func button(
        _ title: String,
        systemImage: String,
        isDestructive: Bool = false,
        isEnabled: Bool = true,
        perform: @escaping () -> Void
    ) -> ApexContextAction {
        ApexContextAction(
            id: UUID().uuidString,
            title: title,
            systemImage: systemImage,
            isDestructive: isDestructive,
            isEnabled: isEnabled,
            perform: perform
        )
    }

    static var divider: ApexContextAction {
        ApexContextAction(id: UUID().uuidString, title: "", systemImage: "", isDivider: true)
    }
}

private struct ExtraContextActionsKey: EnvironmentKey {
    static let defaultValue: [ApexContextAction] = []
}

extension EnvironmentValues {
    var extraContextActions: [ApexContextAction] {
        get { self[ExtraContextActionsKey.self] }
        set { self[ExtraContextActionsKey.self] = newValue }
    }
}

extension View {
    /// Adds actions to the content menu of a descendant `catalogContextMenu`.
    func appendingContextActions(_ extra: [ApexContextAction]) -> some View {
        modifier(AppendContextActionsModifier(extra: extra))
    }

    @ViewBuilder
    func apexContextMenu(_ actions: [ApexContextAction]) -> some View {
        if actions.isEmpty {
            self
        } else {
            #if os(macOS)
                overlay {
                    MacContextMenuCatcher(actions: actions)
                        .allowsHitTesting(false)
                }
            #else
                contextMenu {
                    ForEach(actions) { action in
                        if action.isDivider {
                            Divider()
                        } else if action.isDestructive {
                            Button(role: .destructive, action: action.perform) {
                                Label(action.title, systemImage: action.systemImage)
                            }
                            .disabled(!action.isEnabled)
                        } else {
                            Button(action: action.perform) {
                                Label(action.title, systemImage: action.systemImage)
                            }
                            .disabled(!action.isEnabled)
                        }
                    }
                }
            #endif
        }
    }
}

private struct AppendContextActionsModifier: ViewModifier {
    @Environment(\.extraContextActions) private var existing
    let extra: [ApexContextAction]

    func body(content: Content) -> some View {
        content.environment(\.extraContextActions, existing + extra)
    }
}

#if os(macOS)
    import AppKit

    private struct MacContextMenuCatcher: NSViewRepresentable {
        let actions: [ApexContextAction]

        func makeNSView(context _: Context) -> RightClickView {
            let view = RightClickView()
            view.actions = actions
            RightClickHub.shared.track(view)
            return view
        }

        func updateNSView(_ view: RightClickView, context _: Context) {
            view.actions = actions
            RightClickHub.shared.track(view)
        }

        static func dismantleNSView(_ view: RightClickView, coordinator _: ()) {
            RightClickHub.shared.untrack(view)
        }
    }

    /// One watcher for every poster. A menu's tracking loop stops a local monitor,
    /// so the watcher is installed again as soon as the menu closes.
    private final class RightClickHub {
        static let shared = RightClickHub()
        private let views = NSHashTable<RightClickView>.weakObjects()
        private var monitor: Any?

        func track(_ view: RightClickView) {
            views.add(view)
            installIfNeeded()
        }

        func untrack(_ view: RightClickView) {
            views.remove(view)
            if views.allObjects.isEmpty { uninstall() }
        }

        func installIfNeeded() {
            guard monitor == nil, !views.allObjects.isEmpty else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        /// A context menu runs its own event loop, and the monitor installed before it stops receiving clicks.
        func reinstall() {
            uninstall()
            installIfNeeded()
        }

        private func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            let controlClick = event.type == .leftMouseDown && event.modifierFlags.contains(.control)
            guard event.type == .rightMouseDown || controlClick else { return event }
            let hit = views.allObjects.filter { view in
                guard view.window === event.window, !view.actions.isEmpty else { return false }
                let point = view.convert(event.locationInWindow, from: nil)
                return view.bounds.contains(point) && view.bounds.width > 1 && view.bounds.height > 1
            }
            guard let view = hit.min(by: {
                ($0.bounds.width * $0.bounds.height) < ($1.bounds.width * $1.bounds.height)
            }) else {
                return event
            }
            view.showMenu(with: event)
            reinstall()
            return nil
        }
    }

    private final class RightClickView: NSView {
        var actions: [ApexContextAction] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                RightClickHub.shared.untrack(self)
            } else {
                RightClickHub.shared.track(self)
            }
        }

        override func layout() {
            super.layout()
            if window != nil { RightClickHub.shared.installIfNeeded() }
        }

        func showMenu(with event: NSEvent) {
            guard !actions.isEmpty else { return }
            let menu = NSMenu()
            for action in actions {
                if action.isDivider {
                    menu.addItem(.separator())
                    continue
                }
                let item = NSMenuItem(title: action.title, action: #selector(runAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = action.id
                item.isEnabled = action.isEnabled
                if !action.systemImage.isEmpty,
                   let image = NSImage(systemSymbolName: action.systemImage, accessibilityDescription: action.title)
                {
                    item.image = image
                }
                menu.addItem(item)
            }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        @objc private func runAction(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            actions.first { $0.id == id }?.perform()
        }
    }
#endif
//
//  CatalogContextMenu.swift
//  Apex
//
//  Right-click (and long-press) actions for a movie or series poster: play,
//  favorite, and watched. Extra actions such as "Remove from Recently Watched"
//  arrive through the environment so one menu is shown.
//

import SwiftData
import SwiftUI

extension View {
    func catalogContextMenu(movie: Movie) -> some View {
        modifier(CatalogContextMenuModifier(movie: movie, series: nil))
    }

    func catalogContextMenu(series: Series) -> some View {
        modifier(CatalogContextMenuModifier(movie: nil, series: series))
    }

    /// Menu of environment-provided actions only (live cards, vote, remove).
    func catalogContextMenu() -> some View {
        modifier(CatalogContextMenuModifier(movie: nil, series: nil))
    }
}

private struct CatalogContextMenuModifier: ViewModifier {
    var movie: Movie?
    var series: Series?
    @Environment(\.extraContextActions) private var extras
    @Environment(\.modelContext) private var modelContext
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif

    @State private var playingMedia: PlayableMedia?
    @State private var sourcePrompt: CrossSourcePrompt?
    @State private var pendingResume = true
    @State private var pendingSeason: Int?
    @State private var pendingEpisode: Int?
    @State private var storedPlaylists: [Playlist] = []
    @State private var storedServers: [MediaServer] = []

    func body(content: Content) -> some View {
        content
            .apexContextMenu(actions)
        .crossSourcePicker(item: $sourcePrompt) { item in
            Task { await playChosen(item) }
        }
            #if !os(macOS)
            .fullScreenCover(item: $playingMedia) { media in
                FullScreenPlayerView(media: media)
            }
            #endif
    }

    private var actions: [ApexContextAction] {
        var items: [ApexContextAction] = []
        if let movie {
            let canResume = movie.watchProgress > 1 && !movie.isWatched
            items.append(.button(canResume ? String(localized: "Resume") : String(localized: "Play"), systemImage: "play.fill") {
                playMovie(movie, resume: true)
            })
            if canResume {
                items.append(.button(String(localized: "Play from Beginning"), systemImage: "gobackward") {
                    playMovie(movie, resume: false)
                })
            }
            items.append(.button(
                movie.isFavorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"),
                systemImage: movie.isFavorite ? "heart.slash" : "heart"
            ) {
                movie.isFavorite.toggle()
                movie.addedToWatchlistDate = movie.isFavorite ? Date() : nil
                try? modelContext.save()
            })
            items.append(.button(
                movie.isWatched ? String(localized: "Mark as Unwatched") : String(localized: "Mark as Watched"),
                systemImage: movie.isWatched ? "eye.slash" : "checkmark.circle"
            ) {
                movie.isWatched.toggle()
                if movie.isWatched {
                    movie.watchProgress = Double(movie.durationSecs ?? 0)
                }
                TraktService.shared.syncWatched(movie: movie, watched: movie.isWatched)
                try? modelContext.save()
            })
        } else if let series {
            items.append(.button(String(localized: "Play"), systemImage: "play.fill") {
                playSeries(series, resume: true)
            })
            items.append(.button(
                series.isFavorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"),
                systemImage: series.isFavorite ? "heart.slash" : "heart"
            ) {
                series.isFavorite.toggle()
                series.addedToWatchlistDate = series.isFavorite ? Date() : nil
                try? modelContext.save()
            })
        }
        if !items.isEmpty, !extras.isEmpty {
            items.append(.divider)
        }
        items.append(contentsOf: extras)
        return items
    }

    private func playMovie(_ movie: Movie, resume: Bool) {
        pendingResume = resume
        let lists = (try? modelContext.fetch(FetchDescriptor<Playlist>())) ?? []
        let servers = (try? modelContext.fetch(FetchDescriptor<MediaServer>())) ?? []
        if let prompt = OtherSources.playbackChoice(
            for: movie,
            playlists: lists,
            mediaServers: servers,
            in: modelContext
        ) {
            storedPlaylists = lists
            storedServers = servers
            sourcePrompt = prompt
            return
        }
        guard let media = media(for: movie, resume: resume) else { return }
        present(media)
    }

    private func playSeries(_ series: Series, resume: Bool) {
        SeriesResume.attachStoredEpisodes(to: series, in: modelContext)
        guard let episode = SeriesResume.episode(in: series) else { return }
        let lists = (try? modelContext.fetch(FetchDescriptor<Playlist>())) ?? []
        let servers = (try? modelContext.fetch(FetchDescriptor<MediaServer>())) ?? []
        pendingSeason = episode.seasonNum
        pendingEpisode = episode.episodeNum
        pendingResume = resume
        if let prompt = OtherSources.playbackChoice(
            for: series,
            playlists: lists,
            mediaServers: servers,
            in: modelContext
        ) {
            storedPlaylists = lists
            storedServers = servers
            sourcePrompt = prompt
            return
        }
        guard let media = media(for: episode, on: series, resume: resume) else { return }
        present(media)
    }

    @MainActor
    private func playChosen(_ item: HomeMediaItem) async {
        switch item {
        case let .movie(chosen):
            guard let media = media(for: chosen, resume: pendingResume) else { return }
            present(media)
        case let .series(chosen):
            guard let season = pendingSeason, let episodeNum = pendingEpisode else { return }
            let playlists = storedPlaylists
            let servers = storedServers
            guard let match = await SeriesEpisodeCatalog.matchingProviderEpisode(
                season: season,
                episode: episodeNum,
                in: chosen,
                context: modelContext,
                playlists: playlists,
                mediaServers: servers
            ) else { return }
            guard let media = media(for: match, on: chosen, resume: pendingResume) else { return }
            present(media)
        case .live:
            break
        }
    }

    private func media(for movie: Movie, resume: Bool) -> PlayableMedia? {
        if movie.isMediaServerCatalogItem {
            return PlayableMedia.fromMediaServerMovie(movie, resumeFromProgress: resume)
        }
        let playlists = (try? modelContext.fetch(FetchDescriptor<Playlist>())) ?? []
        guard let playlist = playlists.first(where: { movie.id.hasPrefix($0.id.uuidString) }) else { return nil }
        return PlayableMedia.from(movie: movie, playlist: playlist, resumeFromProgress: resume)
    }

    private func media(for episode: Episode, on series: Series, resume: Bool) -> PlayableMedia? {
        if series.isMediaServerCatalogItem {
            return PlayableMedia.fromMediaServerEpisode(episode, resumeFromProgress: resume)
        }
        let playlists = (try? modelContext.fetch(FetchDescriptor<Playlist>())) ?? []
        guard let playlist = playlists.first(where: { series.id.hasPrefix($0.id.uuidString) }) else { return nil }
        return PlayableMedia.from(episode: episode, playlist: playlist, resumeFromProgress: resume)
    }

    private func present(_ media: PlayableMedia) {
        if ExternalPlayback.open(media) { return }
        #if os(macOS)
            openWindow(id: "player", value: media)
        #else
            playingMedia = media
        #endif
    }
}
