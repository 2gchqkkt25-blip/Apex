//
//  LiveTVView.swift
//  Apex
//
//  Main view for browsing live TV channels — categories sidebar; channels
//  for the selected category are loaded lazily via @Query.
//

import SwiftData
import SwiftUI

/// How the Live TV detail area presents channels: a scannable list (default) or
/// the EPG timeline grid. Persisted across launches.
enum LiveTVLayoutMode: String, CaseIterable, Identifiable {
    case list
    case guide

    var id: String {
        rawValue
    }

    var label: LocalizedStringKey {
        self == .list ? "List" : "Guide"
    }

    var systemImage: String {
        self == .list ? "list.bullet" : "tablecells"
    }

    static let storageKey = "apex.liveTV.layoutMode"
}

struct LiveTVView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.contentRestriction) private var restriction
    @Environment(ThemeManager.self) private var themeManager
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif
    @Query private var playlists: [Playlist]
    @Query(filter: #Predicate<Category> { $0.typeRaw == "live" && $0.isHidden == false })
    private var categories: [Category]

    /// Drives whether the Favorites / Recently Watched virtual sections appear in
    /// the rail. Capped like Home's collection queries — an unbounded fetch of
    /// every favorite across a 28K library re-runs on every main-context merge.
    @Query private var favoriteStreams: [LiveStream]
    @Query private var recentStreams: [LiveStream]

    init() {
        var favorites = FetchDescriptor<LiveStream>(
            predicate: #Predicate { $0.isFavorite && $0.isHidden == false },
            sortBy: [SortDescriptor(\.name)]
        )
        favorites.fetchLimit = 50
        _favoriteStreams = Query(favorites)

        var recents = FetchDescriptor<LiveStream>(
            predicate: #Predicate { $0.lastWatchedDate != nil && $0.isHidden == false },
            sortBy: [SortDescriptor(\.lastWatchedDate, order: .reverse)]
        )
        recents.fetchLimit = 30
        _recentStreams = Query(recents)
    }

    @AppStorage(PlaylistSelectionStore.key) private var selectedPlaylistID: String = ""
    @State private var selectedSection: LiveTVSection?
    @State private var showingSync = false
    @State private var playingMedia: PlayableMedia?
    @State private var showingSettings = false
    /// Shared list + guide EPG cache — survives list↔guide toggles and category
    /// switches (Build 19). SwiftData remains source of truth.
    @State private var epgCache = LiveTVSectionEPGCache()

    @AppStorage(SortStorageKey.liveCategories) private var categorySortRaw: String = CategorySortOption.playlist.rawValue
    @AppStorage(SortStorageKey.liveContent) private var contentSortRaw: String = ContentSortOption.playlist.rawValue
    @AppStorage(LiveTVLayoutMode.storageKey) private var layoutModeRaw: String = LiveTVLayoutMode.list.rawValue

    private var categorySort: CategorySortOption {
        CategorySortOption(rawValue: categorySortRaw) ?? .playlist
    }

    private var contentSort: ContentSortOption {
        ContentSortOption(rawValue: contentSortRaw) ?? .playlist
    }

    private var layoutMode: LiveTVLayoutMode {
        LiveTVLayoutMode(rawValue: layoutModeRaw) ?? .list
    }

    /// Guide/List segmented switch shared across platforms.
    private var layoutModePicker: some View {
        Picker("Layout", selection: $layoutModeRaw) {
            ForEach(LiveTVLayoutMode.allCases) { mode in
                Label(mode.label, systemImage: mode.systemImage).tag(mode.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// The channel detail area for the selected section, honouring the current
    /// layout mode. Shared by every platform's layout.
    @ViewBuilder
    private func detail(for section: LiveTVSection) -> some View {
        let token = section.id
        ZStack {
            channelList(for: section, sectionToken: token)
                .opacity(layoutMode == .list ? 1 : 0)
                .allowsHitTesting(layoutMode == .list)
                .accessibilityHidden(layoutMode != .list)

            EPGGuideView(
                scope: section.scope,
                playlistPrefix: playlistPrefix,
                playlist: activePlaylist,
                sort: contentSort,
                sectionToken: token,
                epgCache: epgCache
            ) { stream in
                playChannel(stream)
            }
            .opacity(layoutMode == .guide ? 1 : 0)
            .allowsHitTesting(layoutMode == .guide)
            .accessibilityHidden(layoutMode != .guide)
        }
        .id(contentSort.rawValue)
        .onAppear { epgCache.activate(section: token) }
        .onChange(of: token) { _, newToken in
            epgCache.activate(section: newToken)
        }
    }

    @ViewBuilder
    private func channelList(for section: LiveTVSection, sectionToken: String) -> some View {
        #if os(tvOS)
            TVChannelsList(
                scope: section.scope,
                playlistPrefix: playlistPrefix,
                playlist: activePlaylist,
                sort: contentSort,
                sectionToken: sectionToken,
                epgCache: epgCache
            ) { stream in
                playChannel(stream)
            }
            .frame(maxWidth: .infinity)
        #else
            ChannelsList(
                scope: section.scope,
                playlistPrefix: playlistPrefix,
                playlist: activePlaylist,
                sort: contentSort,
                sectionToken: sectionToken,
                epgCache: epgCache
            ) { stream in
                playChannel(stream)
            }
        #endif
    }

    var body: some View {
        NavigationStack {
            Group {
                if playlists.isEmpty {
                    ContentUnavailableView(
                        "No Playlists",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Add a playlist in Settings to start watching live TV")
                    )
                } else if categories.isEmpty {
                    VStack(spacing: 20) {
                        ContentUnavailableView(
                            "No Channels",
                            systemImage: "antenna.radiowaves.left.and.right",
                            description: Text("Sync your playlist to load live TV channels")
                        )
                    }
                } else {
                    // Resolve the rail's sections (and the displayed one) once
                    // per render — both `displayedSection` and the layouts read
                    // them, and each resolve filters + sorts the categories.
                    let sections = sortedSections
                    let displayed = displayedSection(in: sections)
                    #if os(iOS)
                        iOSLayout(sections: sections, displayed: displayed)
                    #elseif os(tvOS)
                        tvOSLayout(sections: sections, displayed: displayed)
                    #else
                        macOSLayout(sections: sections, displayed: displayed)
                    #endif
                }
            }
            #if !os(tvOS)
                .scrollContentBackground(.hidden)
            #endif
            .background(themeManager.colors.background)
            .platformNavigationTitle("Live TV")
            #if os(iOS)
                // Inline title: the category selector sits directly below the
                // nav bar, so a large title would rubber-band down and float
                // behind the selector when the channel list is overscrolled.
                .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(iOS) || os(macOS)
            .toolbar {
                if !playlists.isEmpty, !categories.isEmpty {
                    ToolbarItem(placement: .principal) {
                        layoutModePicker
                            .frame(maxWidth: 240)
                    }
                }
            }
            #endif
            .libraryToolbar(config: LibraryToolbarConfiguration(
                playlists: playlists,
                selectedPlaylistID: $selectedPlaylistID,
                categorySortRaw: $categorySortRaw,
                contentSortRaw: $contentSortRaw,
                showingSync: $showingSync,
                showingSettings: $showingSettings,
                activePlaylist: activePlaylist
            ))
            .task {
                if selectedSection == nil, let first = sortedSections.first {
                    selectedSection = first
                }
            }
            .onChange(of: selectedPlaylistID) {
                // Switching playlists invalidates the current selection, which
                // belongs to the previous playlist. Reset to the new playlist's
                // first section so the channel list stays in sync.
                selectedSection = sortedSections.first
            }
            #if os(iOS) || os(tvOS)
            .fullScreenCover(item: $playingMedia) { media in
                FullScreenPlayerView(media: media)
            }
            #endif
        }
    }

    // MARK: - Platform-specific layouts

    #if os(iOS)
        private func iOSLayout(sections: [LiveTVSection], displayed: LiveTVSection?) -> some View {
            VStack(spacing: 0) {
                CategoryBar(
                    sections: sections,
                    selectedSection: $selectedSection
                )

                if let displayed {
                    detail(for: displayed)
                } else {
                    ContentUnavailableView(
                        "Select a Category",
                        systemImage: "list.bullet",
                        description: Text("Choose a category from the list")
                    )
                }
            }
        }
    #endif

    private func macOSLayout(sections: [LiveTVSection], displayed: LiveTVSection?) -> some View {
        HStack(spacing: 0) {
            CategorySidebar(
                sections: sections,
                selectedSection: $selectedSection
            )
            .frame(width: 200)
            .zIndex(1) // Ensure sidebar is above the guide's scroll content

            Divider()

            if let displayed {
                detail(for: displayed)
                    .frame(maxWidth: .infinity)
                    .clipped() // Prevent guide from bleeding into sidebar area
            } else {
                ContentUnavailableView(
                    "Select a Category",
                    systemImage: "list.bullet",
                    description: Text("Choose a category from the sidebar")
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    #if os(tvOS)
        /// One shape for both modes: a slim category rail on the leading edge —
        /// topped by a single List/Guide switch — beside the content area, which
        /// shows either the channel list or the programme guide. Sharing one rail
        /// and one switch keeps moving between the two views consistent.
        private func tvOSLayout(sections: [LiveTVSection], displayed: LiveTVSection?) -> some View {
            TVLiveTVScreen(
                sections: sections,
                selectedSection: $selectedSection,
                displayedSection: displayed,
                layoutModeRaw: $layoutModeRaw,
                contentSort: contentSort,
                onPlay: { playChannel($0) },
                playlistPrefix: playlistPrefix,
                playlist: activePlaylist,
                epgCache: epgCache
            )
        }
    #endif

    /// The playlist whose content is currently shown, resolved from the global
    /// selection. Falls back to the first playlist until the user picks one.
    private var activePlaylist: Playlist? {
        playlists.active(for: selectedPlaylistID)
    }

    /// The id prefix every Category / LiveStream of the active playlist shares.
    private var playlistPrefix: String {
        activePlaylist.map { "\($0.id.uuidString)-" } ?? ""
    }

    /// Categories scoped to the active playlist. The `@Query` fetches every
    /// playlist's categories (SwiftData can't parameterize a `@Query` on view
    /// state), so we isolate by the playlist-prefixed category `id` here.
    private var sortedCategories: [Category] {
        guard let playlistId = activePlaylist?.id else { return [] }
        let prefix = "\(playlistId.uuidString)-"
        return categorySort.sort(categories.filter { $0.id.hasPrefix(prefix) && !restriction.hides(categoryID: $0.id) })
    }

    /// Whether the active playlist has any favorited / recently-watched channels,
    /// gating the corresponding virtual sections so empty collections never show.
    /// Channels in restricted categories are excluded while a child profile is
    /// active, so those collections never surface restricted content.
    private var hasFavorites: Bool {
        !playlistPrefix.isEmpty && favoriteStreams.contains {
            $0.id.hasPrefix(playlistPrefix) && !restriction.hides(categoryID: $0.categoryId)
        }
    }

    private var hasRecents: Bool {
        !playlistPrefix.isEmpty && recentStreams.contains {
            $0.id.hasPrefix(playlistPrefix) && !restriction.hides(categoryID: $0.categoryId)
        }
    }

    /// The rail's entries: the virtual collections (when non-empty) pinned above
    /// the synced categories.
    private var sortedSections: [LiveTVSection] {
        var sections: [LiveTVSection] = []
        sections.append(.all)
        if hasFavorites { sections.append(.favorites) }
        if hasRecents { sections.append(.recentlyWatched) }
        sections.append(contentsOf: sortedCategories.map(LiveTVSection.category))
        return sections
    }

    /// The section to render in the detail pane. Normally the user's selection,
    /// but if that section just disappeared (a category hidden in Content
    /// Management, or the last favorite removed) fall back to the first available
    /// one rather than keep showing stale content.
    private func displayedSection(in sections: [LiveTVSection]) -> LiveTVSection? {
        guard let selectedSection else { return sections.first }
        return sections.contains { $0.id == selectedSection.id }
            ? selectedSection
            : sections.first
    }

    private func playChannel(_ stream: LiveStream) {
        guard let playlist = activePlaylist,
              let media = PlayableMedia.from(stream: stream, playlist: playlist) else { return }
        // Set the surf scope so channel up/down stays within the current section
        // (favorites, recently watched, or a specific category).
        if let section = selectedSection {
            LiveChannelNavigator.activeSurfScope = section.scope
        } else {
            LiveChannelNavigator.activeSurfScope = nil
        }
        if ExternalPlayback.open(media) { return }
        #if os(macOS)
            openWindow(id: "player", value: media)
        #else
            playingMedia = media
        #endif
    }
}

// MARK: - Category Sidebar

struct CategorySidebar: View {
    let sections: [LiveTVSection]
    @Binding var selectedSection: LiveTVSection?
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false

    /// Only category sections (not virtual Favorites/Recently Watched/All) are reorderable.
    private var reorderableSections: [LiveTVSection] {
        sections.filter { if case .category = $0 { return true } else { return false } }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isEditing {
                // Edit mode: reorder with move buttons
                ScrollView {
                    LazyVStack(spacing: 2) {
                        // Done button at top of scroll
                        HStack {
                            Text("Reorder Categories")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Done")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(themeManager.colors.accent)
                                .onTapGesture { isEditing = false }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)

                        ForEach(Array(reorderableSections.enumerated()), id: \.element.id) { index, section in
                            HStack(spacing: 8) {
                                VStack(spacing: 2) {
                                    Button {
                                        guard index > 0 else { return }
                                        moveCategoryAt(index, to: index - 1)
                                    } label: {
                                        Image(systemName: "chevron.up")
                                            .font(.caption2.weight(.bold))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(index == 0)

                                    Button {
                                        guard index < reorderableSections.count - 1 else { return }
                                        moveCategoryAt(index, to: index + 1)
                                    } label: {
                                        Image(systemName: "chevron.down")
                                            .font(.caption2.weight(.bold))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(index == reorderableSections.count - 1)
                                }
                                .foregroundStyle(.secondary)

                                if let icon = section.icon {
                                    Image(systemName: icon)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Text(section.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            } else {
                // Normal mode: category selection
                ScrollView {
                    LazyVStack(spacing: 2) {
                        // Edit button at top of scroll content
                        HStack {
                            Spacer()
                            Text("Edit")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(themeManager.colors.accent)
                                .onTapGesture { isEditing = true }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)

                        ForEach(sections) { section in
                            let isSelected = selectedSection?.id == section.id
                            HStack(spacing: 8) {
                                if let icon = section.icon {
                                    Image(systemName: icon)
                                        .font(.subheadline)
                                        .foregroundStyle(isSelected ? themeManager.colors.accent : Color.secondary)
                                }
                                Text(section.title)
                                    .font(.headline)
                                    .foregroundStyle(isSelected ? themeManager.colors.accent : Color.primary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? themeManager.colors.accent.opacity(0.15) : Color.clear)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedSection = section
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        #if os(macOS)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        #endif
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        var ordered = reorderableSections
        ordered.move(fromOffsets: source, toOffset: destination)
        persistCategoryOrder(ordered)
    }

    private func moveCategoryAt(_ fromIndex: Int, to toIndex: Int) {
        var ordered = reorderableSections
        let item = ordered.remove(at: fromIndex)
        ordered.insert(item, at: toIndex)
        persistCategoryOrder(ordered)
    }

    private func persistCategoryOrder(_ ordered: [LiveTVSection]) {
        for (index, section) in ordered.enumerated() {
            if case let .category(cat) = section {
                let categoryId = cat.id
                let descriptor = FetchDescriptor<Category>(
                    predicate: #Predicate { $0.id == categoryId }
                )
                if let found = try? modelContext.fetch(descriptor).first {
                    found.customOrder = index
                }
            }
        }
        try? modelContext.save()
    }
}

// MARK: - iOS Category Bar

#if os(iOS)
    /// iOS category selector. A horizontal pill strip is unscannable once a
    /// playlist syncs hundreds of categories, so the current section is shown as a
    /// single button that opens a searchable list of every section instead.
    struct CategoryBar: View {
        let sections: [LiveTVSection]
        @Binding var selectedSection: LiveTVSection?

        @State private var showingPicker = false

        /// The section the button reflects — the user's selection, or the first
        /// available one if that selection has since disappeared (mirrors
        /// `displayedSection(in:)`).
        private var currentSection: LiveTVSection? {
            guard let selectedSection else { return sections.first }
            return sections.first { $0.id == selectedSection.id } ?? sections.first
        }

        var body: some View {
            Button {
                showingPicker = true
            } label: {
                HStack(spacing: 8) {
                    if let icon = currentSection?.icon {
                        Image(systemName: icon)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    (currentSection?.titleText ?? Text("Select a Category"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(.bar)
            .sheet(isPresented: $showingPicker) {
                CategoryPickerSheet(sections: sections, selectedSection: $selectedSection)
            }

            Divider()
        }
    }

    /// Searchable list of every Live TV section. Type to filter hundreds of
    /// synced categories down to a handful; the virtual collections stay pinned
    /// at the top while the search field is empty.
    private struct CategoryPickerSheet: View {
        let sections: [LiveTVSection]
        @Binding var selectedSection: LiveTVSection?

        @Environment(\.dismiss) private var dismiss
        @Environment(\.modelContext) private var modelContext
        @State private var query = ""
        @State private var isEditing = false

        private var filteredSections: [LiveTVSection] {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return sections }
            return sections.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
        }

        /// Only category sections (not virtual Favorites/Recently Watched) are reorderable.
        private var reorderableSections: [LiveTVSection] {
            sections.filter { if case .category = $0 { return true } else { return false } }
        }

        var body: some View {
            NavigationStack {
                List {
                    if !isEditing {
                        ForEach(filteredSections) { section in
                            let isSelected = selectedSection?.id == section.id
                            Button {
                                selectedSection = section
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    if let icon = section.icon {
                                        Image(systemName: icon)
                                            .foregroundStyle(.secondary)
                                    }
                                    section.titleText
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        // Edit mode: drag-to-reorder category sections
                        Section {
                            ForEach(reorderableSections) { section in
                                HStack(spacing: 12) {
                                    if let icon = section.icon {
                                        Image(systemName: icon)
                                            .foregroundStyle(.secondary)
                                    }
                                    section.titleText
                                        .foregroundStyle(.primary)
                                }
                            }
                            .onMove(perform: moveCategories)
                        } header: {
                            Text("Drag to reorder")
                        }
                    }
                }
                .listStyle(.plain)
                .environment(\.editMode, isEditing ? .constant(.active) : .constant(.inactive))
                .overlay {
                    if filteredSections.isEmpty, !isEditing {
                        ContentUnavailableView.search(text: query)
                    }
                }
                .searchable(text: $query, prompt: "Search categories")
                .navigationTitle(isEditing ? "Reorder" : "Categories")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if isEditing {
                            Button("Done") { isEditing = false }
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if !isEditing {
                            Menu {
                                Button { isEditing = true } label: {
                                    Label("Reorder", systemImage: "arrow.up.arrow.down")
                                }
                                Button("Done") { dismiss() }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
        }

        private func moveCategories(from source: IndexSet, to destination: Int) {
            var ordered = reorderableSections
            ordered.move(fromOffsets: source, toOffset: destination)
            // Persist the new order onto the Category model's customOrder field
            for (index, section) in ordered.enumerated() {
                if case let .category(cat) = section {
                    let categoryId = cat.id
                    let descriptor = FetchDescriptor<Category>(
                        predicate: #Predicate { $0.id == categoryId }
                    )
                    if let found = try? modelContext.fetch(descriptor).first {
                        found.customOrder = index
                    }
                }
            }
            try? modelContext.save()
        }
    }
#endif

// MARK: - Channels List

struct ChannelsList: View {
    let scope: LiveChannelScope
    let playlistPrefix: String
    let playlist: Playlist?
    let sectionToken: String
  @Bindable var epgCache: LiveTVSectionEPGCache
    let onPlay: (LiveStream) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.contentRestriction) private var restriction
    @Query private var streams: [LiveStream]
    /// Observed only so the list can refresh after a manual guide sync finishes.
    @State private var epgSync = EPGSyncService.shared
    /// How many channels are currently rendered. Grows by a page as the list
    /// nears its end so a large category loads lazily instead of all at once.
    @State private var visibleCount = LiveChannelQuery.pageSize

    init(
        scope: LiveChannelScope,
        playlistPrefix: String,
        playlist: Playlist?,
        sort: ContentSortOption,
        sectionToken: String,
        epgCache: LiveTVSectionEPGCache,
        onPlay: @escaping (LiveStream) -> Void
    ) {
        self.scope = scope
        self.playlistPrefix = playlistPrefix
        self.playlist = playlist
        self.sectionToken = sectionToken
        self._epgCache = Bindable(epgCache)
        self.onPlay = onPlay
        _streams = Query(LiveChannelQuery.descriptor(for: scope, sort: sort, playlistPrefix: playlistPrefix))
    }

    private var scopedStreams: [LiveStream] {
        LiveChannelQuery.scoped(streams, scope: scope, playlistPrefix: playlistPrefix)
            .excludingRestricted(restriction)
    }

    /// Clears a channel's watch timestamp so it drops out of the Recently
    /// Watched list. The @Query-backed list updates once the change is saved.
    private func removeFromRecentlyWatched(_ stream: LiveStream) {
        stream.lastWatchedDate = nil
        try? modelContext.save()
    }

    var body: some View {
        let channels = scopedStreams
        let visible = Array(channels.prefix(visibleCount))
        Group {
            #if os(iOS)
                channelListIOS(visible: visible, channels: channels)
            #else
                channelListScroll(visible: visible, channels: channels)
            #endif
        }
        .task(id: sectionToken) {
            epgCache.activate(section: sectionToken)
            await loadEPG(for: visible)
            await ChannelLogoLoader.prefetch(visible.compactMap(\.iconURL))
            await recomputeEPGPeriodically()
        }
        .onChange(of: sectionToken) {
            visibleCount = LiveChannelQuery.pageSize
        }
        .onChange(of: epgSync.refreshGeneration) {
            Task { await loadEPG(for: visible, force: true) }
        }
        .onChange(of: visibleCount) { _, count in
            let page = Array(scopedStreams.prefix(count))
            Task { await loadEPG(for: page) }
        }
    }

    #if os(iOS)
        /// `List` lays out `UIImageView`-backed logos reliably; `LazyVStack` in a
        /// `ScrollView` often gives channel icons a zero-size slot on iOS.
        private func channelListIOS(visible: [LiveStream], channels: [LiveStream]) -> some View {
            List {
                if channels.isEmpty {
                    ContentUnavailableView(
                        "No Channels",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("This category has no channels")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(visible) { stream in
                        LiveStreamCardView(stream: stream, epg: epgCache.epgByChannel[stream.primaryEPGChannelId])
                            .contentShape(Rectangle())
                            .onTapGesture { onPlay(stream) }
                            .id(stream.id)
                            .recentlyWatchedRemoveMenu(scope == .recentlyWatched ? { removeFromRecentlyWatched(stream) } : nil)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .onAppear {
                                if stream.id == visible.last?.id, visibleCount < channels.count {
                                    visibleCount = min(visibleCount + LiveChannelQuery.pageSize, channels.count)
                                }
                            }
                    }
                }
            }
            .listStyle(.plain)
            #if !os(tvOS)
                .scrollContentBackground(.hidden)
            #endif
        }
    #endif

    private func channelListScroll(visible: [LiveStream], channels: [LiveStream]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if channels.isEmpty {
                    ContentUnavailableView(
                        "No Channels",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("This category has no channels")
                    )
                } else {
                    ForEach(visible) { stream in
                        LiveStreamCardView(stream: stream, epg: epgCache.epgByChannel[stream.primaryEPGChannelId])
                            .padding(.horizontal)
                            .contentShape(Rectangle())
                            .onTapGesture { onPlay(stream) }
                            .id(stream.id)
                            .recentlyWatchedRemoveMenu(scope == .recentlyWatched ? { removeFromRecentlyWatched(stream) } : nil)
                            .onAppear {
                                if stream.id == visible.last?.id, visibleCount < channels.count {
                                    visibleCount = min(visibleCount + LiveChannelQuery.pageSize, channels.count)
                                }
                            }

                        Divider()
                            .padding(.leading, 88)
                    }
                }
            }
        }
    }

    /// Re-derives now/next from already-fetched programme lists once a minute,
    /// with no network call. Without this, a card kept showing whatever was
    /// "now" at the last fetch even after that programme ended — the guide
    /// looked fresh but the label the user saw before tapping play could be
    /// well out of date.
    private func recomputeEPGPeriodically() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            recomputeEPGFromCache()
        }
    }

    private func recomputeEPGFromCache() {
        epgCache.recomputeNowNext()
    }

    /// Loads EPG for channels missing from the shared section cache.
    private func loadEPG(for channels: [LiveStream], force: Bool = false) async {
        guard !channels.isEmpty else { return }
        let targets = force ? channels : epgCache.channelsNeedingLoad(channels)
        guard !targets.isEmpty else { return }

        let loaded = await EPGBrowseLoader.load(
            container: modelContext.container,
            channels: targets,
            playlist: playlist
        )
        guard !Task.isCancelled else { return }

        epgCache.merge(section: sectionToken, loaded: loaded)
    }
}

#Preview("Empty") {
    LiveTVView()
        .modelContainer(for: Playlist.self, inMemory: true)
}

#Preview("With Data") {
    LiveTVView()
        .modelContainer(previewContainer())
}

#Preview("No Playlists") {
    LiveTVView()
}
