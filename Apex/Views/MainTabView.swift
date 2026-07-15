//
//  MainTabView.swift
//  Apex
//
//  Main tab-based navigation for the app
//

import SwiftData
import SwiftUI

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    // Optional so previews (which don't inject it) don't crash.
    @Environment(PlaylistSwitchModel.self) private var playlistSwitch: PlaylistSwitchModel?
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?
    @Environment(ThemeManager.self) private var themeManager
    @Query private var playlists: [Playlist]
    /// Categories marked restricted. Fetched once here so a single source feeds
    /// the restriction context every content surface reads from the environment.
    @Query(filter: #Predicate<Category> { $0.isRestricted }) private var restrictedCategories: [Category]

    @AppStorage(SyncFrequency.storageKey) private var syncFrequencyRaw: String = SyncFrequency.defaultValue.rawValue
    @AppStorage(PlaylistSelectionStore.key) private var selectedPlaylistID: String = ""

    /// Selected tab and the Movies/Series navigation stacks, shared so an
    /// `onOpenURL` deep link can switch tabs and push a detail screen.
    @State private var router = DeepLinkRouter()

    /// Playlists waiting to be auto-synced, and the one currently shown in the
    /// blocking progress cover. Auto-sync is presented (not silent) so the user
    /// sees progress and waits for it to finish — most importantly right after
    /// adding a playlist, when the app would otherwise look empty and broken.
    @State private var syncQueue: [Playlist] = []
    @State private var activeSyncPlaylist: Playlist?

    /// Playlists we've already auto-synced (or attempted) this session, so the
    /// launch / switch / foreground triggers don't re-present the cover for one
    /// that's already been handled.
    @State private var autoSyncAttempted: Set<UUID> = []

    /// Browse tabs mount on first selection and **unmount when not selected**.
    /// Other IPTV apps handle 17K+ channels without crashing because they only
    /// keep the current screen's data in memory. SwiftData's `@Query` keeps all
    /// results resident for the lifetime of the view — with 44K+ objects across
    /// multiple tabs, the combined memory exceeds jetsam limits. Deactivating
    /// inactive tabs releases their query subscriptions and backing objects.
    ///
    /// The Home tab stays mounted (lightweight hero + small collection queries).
    /// Every other tab unmounts when the user navigates away — its view (and all
    /// `@Query` results) are deallocated. Re-mounting on return is fast because
    /// SwiftData's SQLite backing reads from disk cache.
    @State private var activatedTabs: Set<AppTab> = [.home]

    private var syncFrequency: SyncFrequency {
        SyncFrequency.resolve(syncFrequencyRaw)
    }

    /// UI tests seed a fake playlist; auto-sync would present a blocking cover
    /// that can never succeed against the stub server, so skip it there.
    private var isUITesting: Bool {
        CommandLine.arguments.contains("-ui-testing")
    }

    /// Hides restricted categories (and their content) from every browse, Home
    /// and Search surface while a child profile is active.
    private var contentRestriction: ContentRestriction {
        ContentRestriction(
            isActive: profileManager?.activeProfileIsChild ?? false,
            restrictedCategoryIDs: Set(restrictedCategories.map(\.id))
        )
    }

    var body: some View {
        @Bindable var router = router
        return tabView(selection: $router.selectedTab)
            .tint(themeManager.colors.accent)
            .environment(router)
            .environment(\.contentRestriction, contentRestriction)
            .themeBackground()
        #if os(iOS)
            .tabBarMinimizeOnScrollDownIfAvailable()
        #endif
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .task(id: playlists.map(\.id)) {
                // On launch (and whenever a playlist is added/removed) pin a
                // preferred default if needed, then sync any playlist that is
                // due per the configured frequency.
                settleDefaultPlaylistSelection()
                enqueueDueSyncs(playlists)
            }
            .onChange(of: selectedPlaylistID) {
                // On playlist switch, sync the newly selected one if it's due.
                if let playlist = playlists.active(for: selectedPlaylistID) {
                    enqueueDueSyncs([playlist])
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Returning to the foreground re-checks staleness — for a long-lived
                // app this is the practical equivalent of "on launch".
                if phase == .active {
                    settleDefaultPlaylistSelection()
                    enqueueDueSyncs(playlists)
                }
            }
            .onChange(of: router.selectedTab) { _, _ in
                // tvOS may defer refresh covers until Settings; promote when the
                // user navigates so a queued restore sync can still start.
                promoteNextIfIdle()
            }
            .syncCover(item: $activeSyncPlaylist, onDismiss: handleSyncCoverDismissed)
            .overlay {
                if playlistSwitch?.isSwitching == true {
                    PlaylistSwitchOverlay(playlistName: playlistSwitch?.targetName ?? "")
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: playlistSwitch?.isSwitching)
    }

    #if os(tvOS)
        private func tabView(selection: Binding<AppTab>) -> some View {
            TabView(selection: selection) {
                Tab(value: AppTab.search) {
                    lazyTab(.search, selection: selection.wrappedValue) { SearchView() }
                } label: {
                    Image(systemName: "magnifyingglass")
                }

                Tab(value: AppTab.home) {
                    lazyTab(.home, selection: selection.wrappedValue) { HomeView() }
                } label: {
                    Text("Home")
                }

                Tab(value: AppTab.movies) {
                    lazyTab(.movies, selection: selection.wrappedValue) { MoviesView() }
                } label: {
                    Text("Movies")
                }

                Tab(value: AppTab.series) {
                    lazyTab(.series, selection: selection.wrappedValue) { SeriesView() }
                } label: {
                    Text("Series")
                }

                Tab(value: AppTab.liveTV) {
                    lazyTab(.liveTV, selection: selection.wrappedValue) { LiveTVView() }
                } label: {
                    Text("Live TV")
                }

                Tab(value: AppTab.settings) {
                    lazyTab(.settings, selection: selection.wrappedValue) { SettingsView() }
                } label: {
                    Image(systemName: "gear")
                }
            }
            .onChange(of: selection.wrappedValue) { _, tab in
                activatedTabs.insert(tab)
                ContentIndexingService.shared.pauseForBrowse()
            }
        }
    #else
        private func tabView(selection: Binding<AppTab>) -> some View {
            TabView(selection: selection) {
                Tab("Home", systemImage: "house", value: AppTab.home) {
                    lazyTab(.home, selection: selection.wrappedValue) { HomeView() }
                }

                Tab("Movies", systemImage: "film", value: AppTab.movies) {
                    lazyTab(.movies, selection: selection.wrappedValue) { MoviesView() }
                }

                Tab("Series", systemImage: "tv", value: AppTab.series) {
                    lazyTab(.series, selection: selection.wrappedValue) { SeriesView() }
                }

                Tab("Live TV", systemImage: "antenna.radiowaves.left.and.right", value: AppTab.liveTV) {
                    lazyTab(.liveTV, selection: selection.wrappedValue) { LiveTVView() }
                }

                Tab(value: AppTab.search, role: .search) {
                    lazyTab(.search, selection: selection.wrappedValue) { SearchView() }
                }
            }
            .onChange(of: selection.wrappedValue) { _, tab in
                activatedTabs.insert(tab)
                ContentIndexingService.shared.pauseForBrowse()
            }
        }
    #endif

    /// Defers mounting a tab's browse surface until the user selects it (or a
    /// deep link targets it). Home is always mounted so the launch screen is
    /// usable immediately after sync.
    ///
    /// Mounts the tab's content only when it is the active selection. Inactive
    /// tabs unmount so their `@Query` subscriptions release memory. Home stays
    /// mounted (its queries are all capped and lightweight). The re-mount on
    /// selection is instant — SwiftData reads from SQLite's page cache.
    @ViewBuilder
    private func lazyTab(_ tab: AppTab, selection: AppTab, @ViewBuilder content: () -> some View) -> some View {
        if selection == tab || tab == .home {
            content()
        } else {
            Color.clear
        }
    }

    private func activateTab(_ tab: AppTab) {
        activatedTabs.insert(tab)
    }

    // MARK: - Deep links

    /// Resolves a `apex://movie/{tmdbId}` / `apex://series/{tmdbId}` link to a
    /// catalog item, switches to the matching tab and pushes its detail screen.
    /// Silently ignores unknown links and titles not present in the catalog
    /// (e.g. a tmdbId that was never synced or enriched).
    private func handleDeepLink(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case let .movie(tmdbId):
            guard let movie = resolveMovie(tmdbId: tmdbId) else { return }
            activateTab(.movies)
            router.selectedTab = .movies
            router.moviesPath = NavigationPath()
            router.moviesPath.append(movie)
        case let .series(tmdbId):
            guard let series = resolveSeries(tmdbId: tmdbId) else { return }
            activateTab(.series)
            router.selectedTab = .series
            router.seriesPath = NavigationPath()
            router.seriesPath.append(series)
        }
    }

    /// Finds a movie by `tmdbId`, preferring the active playlist but falling back
    /// to any other playlist's copy. Restricted categories stay hidden for a
    /// child profile.
    private func resolveMovie(tmdbId: Int) -> Movie? {
        let descriptor = FetchDescriptor<Movie>(predicate: #Predicate { $0.tmdbId == tmdbId })
        let restriction = contentRestriction
        let matches = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { !restriction.hides(categoryID: $0.categoryId) }
        return matches.first { belongsToActivePlaylist($0.id) } ?? matches.first
    }

    private func resolveSeries(tmdbId: Int) -> Series? {
        let descriptor = FetchDescriptor<Series>(predicate: #Predicate { $0.tmdbId == tmdbId })
        let restriction = contentRestriction
        let matches = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { !restriction.hides(categoryID: $0.categoryId) }
        return matches.first { belongsToActivePlaylist($0.id) } ?? matches.first
    }

    private func belongsToActivePlaylist(_ id: String) -> Bool {
        guard let activePlaylist = playlists.active(for: selectedPlaylistID) else { return true }
        return id.hasPrefix("\(activePlaylist.id.uuidString)-")
    }

    // MARK: - Automatic sync

    /// Pins `apex.selectedPlaylistID` when empty or orphaned so a CloudKit
    /// restore that materializes Stremio before Xtream does not leave Stremio
    /// as the lasting default (`.active(for:)` alone is non-persisting).
    ///
    /// Also promotes Stremio → preferred catalog playlist when that catalog
    /// entry has never synced locally (progressive iCloud import).
    private func settleDefaultPlaylistSelection() {
        guard let preferred = playlists.preferredDefault() else { return }

        if selectedPlaylistID.isEmpty
            || !playlists.contains(where: { $0.id.uuidString == selectedPlaylistID }) {
            selectedPlaylistID = preferred.id.uuidString
            return
        }

        guard preferred.sourceType != .stremio, preferred.lastSyncDate == nil else { return }
        guard let current = playlists.first(where: { $0.id.uuidString == selectedPlaylistID }),
              current.sourceType == .stremio
        else { return }
        selectedPlaylistID = preferred.id.uuidString
    }

    /// Enqueues every due playlist for a blocking, progress-visible sync and
    /// presents the first one. Covers the never-synced first launch (where
    /// `lastSyncDate == nil` makes a playlist due) as well as periodic refreshes.
    /// Catalog playlists (Xtream / M3U / Stalker) are queued ahead of Stremio.
    private func enqueueDueSyncs(_ candidates: [Playlist]) {
        guard !isUITesting else { return }

        for playlist in candidates.orderedForAutoSync() where shouldAutoSync(playlist) {
            autoSyncAttempted.insert(playlist.id)
            if !syncQueue.contains(where: { $0.id == playlist.id }) {
                syncQueue.append(playlist)
            }
        }
        syncQueue = syncQueue.orderedForAutoSync()
        promoteNextIfIdle()
    }

    private func shouldAutoSync(_ playlist: Playlist) -> Bool {
        AutoSync.shouldSync(
            syncEnabled: playlist.syncEnabled,
            status: playlist.syncStatus,
            lastSyncDate: playlist.lastSyncDate,
            frequency: syncFrequency,
            alreadyStarted: autoSyncAttempted.contains(playlist.id)
        )
    }

    /// Presents the next queued playlist's sync cover when none is showing. The
    /// `SyncProgressView` auto-starts the sync and dismisses itself on success;
    /// the cover's `onDismiss` calls back here to advance the queue.
    private func promoteNextIfIdle() {
        guard activeSyncPlaylist == nil, !syncQueue.isEmpty else { return }
        #if os(tvOS)
        // Defer periodic *refresh* covers while browsing (don't interrupt Home).
        // Always present first-time syncs (`lastSyncDate == nil`) so CloudKit-
        // restored Xtream/M3U catalogs pull immediately after install. Also
        // present when the user is already in Settings.
        let next = syncQueue[0]
        let isFirstTimeSync = next.lastSyncDate == nil
        if !isFirstTimeSync, router.selectedTab != .settings, scenePhase == .active {
            return
        }
        #endif
        activeSyncPlaylist = syncQueue.removeFirst()
    }

    private func handleSyncCoverDismissed() {
        promoteNextIfIdle()
    }
}

// MARK: - Sync cover presentation

private extension View {
    /// Presents the auto-sync progress UI as a blocking cover: a full-screen
    /// cover on iOS/tvOS (no swipe-to-dismiss), a sheet on macOS where
    /// `fullScreenCover` is unavailable.
    @ViewBuilder
    func syncCover(item: Binding<Playlist?>, onDismiss: @escaping () -> Void) -> some View {
        #if os(macOS)
            sheet(item: item, onDismiss: onDismiss) { playlist in
                SyncProgressView(playlist: playlist, autoStart: true)
                    .frame(minWidth: 420, minHeight: 480)
            }
        #else
            fullScreenCover(item: item, onDismiss: onDismiss) { playlist in
                SyncProgressView(playlist: playlist, autoStart: true)
            }
        #endif
    }
}

#Preview("No Playlists") {
    MainTabView()
}

#Preview("With Playlists") {
    MainTabView()
        .modelContainer(for: Playlist.self, inMemory: true) { result in
            if case let .success(container) = result {
                let playlist = Playlist(name: "My IPTV", serverURL: "http://example.com:8080", username: "user", password: "pass")
                container.mainContext.insert(playlist)
            }
        }
}
