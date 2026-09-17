//
//  EPGGuideView.swift
//  Apex
//
//  A classic "TV guide" grid for a category: a frozen channel column on the
//  left, a frozen time ruler across the top, and programme blocks sized to
//  their duration. A live "now" line tracks the current moment.
//
//  Guide data: SwiftData first, then on-demand API for gaps (`EPGBrowseLoader`).
//  Channel logos paint immediately; programmes fill in after fetch.
//  See `EPG.md` for architecture and stale-timestamp alignment.
//

import SwiftData
import SwiftUI
#if os(iOS)
    import UIKit
#endif

struct EPGGuideView: View {
    let scope: LiveChannelScope
    let playlistPrefix: String
    let playlist: Playlist?
    let sectionToken: String
    @Bindable var epgCache: LiveTVSectionEPGCache
    let onPlay: (LiveStream) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var streams: [LiveStream]

    @State private var timeline: EPGTimeline

    @State private var visibleCount = LiveChannelQuery.pageSize
    @State private var epgSync = EPGSyncService.shared
    /// Coalesces mid-sync / gap-fill refresh bumps so the guide focus tree isn't
    /// rebuilt on every signal while the user is scrolling.
    @State private var pendingRefreshTask: Task<Void, Never>?

    init(
        scope: LiveChannelScope,
        playlistPrefix: String,
        playlist: Playlist? = nil,
        sort: ContentSortOption,
        sectionToken: String,
        epgCache: LiveTVSectionEPGCache,
        onPlay: @escaping (LiveStream) -> Void
    ) {
        self.scope = scope
        self.playlistPrefix = playlistPrefix
        self.playlist = playlist
        self.sectionToken = sectionToken
        _epgCache = Bindable(epgCache)
        self.onPlay = onPlay

        // 12h ahead balances showing upcoming programmes with smooth scrolling.
        // The original 5h hid most future data; 18–48h generated too many cells
        // on iOS/macOS at 3.0–3.4 pts/min and caused jank. With the store cap
        // raised to 64 listings/channel, 12h has enough data to render fully.
        let timeline = EPGTimeline.live(now: Date(), pointsPerMinute: EPGMetrics.current.pointsPerMinute, hoursBehind: 6, hoursAhead: 12)
        _timeline = State(initialValue: timeline)

        _streams = Query(LiveChannelQuery.descriptor(for: scope, sort: sort, playlistPrefix: playlistPrefix))
    }

    private var scopedStreams: [LiveStream] {
        LiveChannelQuery.scoped(streams, scope: scope, playlistPrefix: playlistPrefix)
    }

    var body: some View {
        let channels = scopedStreams
        let visible = Array(channels.prefix(visibleCount))
        let displayRows = EPGGridBuilder.rows(
            streams: visible,
            programsByChannel: epgCache.programsByChannel,
            timeline: timeline
        )

        if channels.isEmpty {
            ContentUnavailableView(
                "No Channels",
                systemImage: "antenna.radiowaves.left.and.right",
                description: Text("This category has no channels")
            )
        } else {
            EPGGridScroller(
                rows: displayRows,
                timeline: timeline,
                onPlay: onPlay,
                onNearEnd: {
                    guard visibleCount < channels.count else { return }
                    visibleCount = min(visibleCount + LiveChannelQuery.pageSize, channels.count)
                }
            )
            .onAppear {
                // Activate cached section data synchronously on appear so the
                // first frame renders with programme cells (not blank gaps).
                // The .task below then fills any remaining gaps from the store.
                epgCache.activate(section: sectionToken)
            }
            .task(id: sectionToken) {
                epgCache.activate(section: sectionToken)
                await loadGuide(for: visible)
            }
            .onChange(of: sectionToken) {
                visibleCount = LiveChannelQuery.pageSize
            }
            .onChange(of: epgSync.refreshGeneration) {
                pendingRefreshTask?.cancel()
                pendingRefreshTask = Task {
                    // Debounce: mid-sync signals + browse gap-fill can fire close
                    // together; applying each immediately remounts programme cells
                    // under the tvOS focus engine and makes guide scroll feel broken.
                    try? await Task.sleep(for: .milliseconds(450))
                    guard !Task.isCancelled else { return }
                    await loadGuide(for: visible, force: true)
                }
            }
            .onChange(of: visibleCount) { _, count in
                let page = Array(scopedStreams.prefix(count))
                Task { await loadGuide(for: page) }
            }
            .onDisappear {
                pendingRefreshTask?.cancel()
                pendingRefreshTask = nil
            }
        }
    }

    @MainActor
    private func loadGuide(for channels: [LiveStream], force: Bool = false) async {
        guard !channels.isEmpty else { return }

        let targets = force ? channels : epgCache.channelsNeedingLoad(channels)
        guard !targets.isEmpty else { return }

        // Same `EPGBrowseLoader.load` path as the list — identical store window
        // and speed. The grid clamps programmes to `timeline` when rendering.
        // `force` reloads from store/warm cache only (no new gap-fill) so mid-sync
        // refreshGeneration bumps don't re-trigger live API → forceGuideRefresh.
        let loaded = await EPGBrowseLoader.load(
            container: modelContext.container,
            channels: targets,
            playlist: playlist,
            allowGapFill: !force
        )
        guard !Task.isCancelled else { return }

        if force {
            epgCache.mergeLiveStatus(section: sectionToken, loaded: loaded)
        } else {
            epgCache.merge(section: sectionToken, loaded: loaded)
        }

        let logoURLs = channels.compactMap(\.iconURL)
        guard !logoURLs.isEmpty else { return }
        Task {
            await ChannelLogoLoader.prefetch(logoURLs)
        }
    }
}

// MARK: - Selection

/// A tapped programme, carried to the detail sheet.
private struct EPGSelection: Identifiable {
    let id: String
    let stream: LiveStream
    let cell: EPGProgramCell
}

// MARK: - Scroll sync

/// Shared, observable scroll offset. Only the ruler and channel column observe
/// it, so panning the grid updates *their* offset modifiers without re-running
/// the (expensive) programme grid. See `skills/swiftui-performance.md`.
@MainActor
@Observable
final class EPGScrollSync {
    /// Split axes are intentional. Observation tracks these properties
    /// independently, so vertical scrolling doesn't rebuild the ruler and
    /// horizontal scrolling doesn't rebuild the frozen channel column.
    var horizontalOffset: CGFloat = 0
    var verticalOffset: CGFloat = 0
}

#if os(iOS)
    /// Reaches the native scroll view backing SwiftUI's two-axis guide and asks
    /// it to lock a pan to the user's dominant axis. It also owns horizontal
    /// jump-to-now on iOS, avoiding SwiftUI's `ScrollPosition` binding: that
    /// binding re-anchors to changing programme identities while EPG data fills
    /// in, which makes a horizontal drag visibly jump.
    struct EPGScrollDirectionLock: UIViewRepresentable {
        var initialHorizontalOffset: CGFloat? = nil
        var jumpToken = 0

        final class Coordinator {
            weak var scrollView: UIScrollView?
            var didApplyInitialOffset = false
            var appliedJumpToken: Int?
        }

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeUIView(context _: Context) -> UIView {
            ProbeView()
        }

        func updateUIView(_ view: UIView, context: Context) {
            (view as? ProbeView)?.configureNearestScrollView(
                initialHorizontalOffset: initialHorizontalOffset,
                jumpToken: jumpToken,
                coordinator: context.coordinator
            )
        }

        private final class ProbeView: UIView {
            func configureNearestScrollView(
                initialHorizontalOffset: CGFloat?,
                jumpToken: Int,
                coordinator: Coordinator
            ) {
                Task { @MainActor [weak self] in
                    // SwiftUI may attach the representable before it attaches
                    // the surrounding ScrollView. Yield once, then walk up.
                    await Task.yield()
                    guard let self else { return }
                    var candidate = superview
                    while let view = candidate {
                        if let scrollView = view as? UIScrollView {
                            scrollView.isDirectionalLockEnabled = true
                            coordinator.scrollView = scrollView
                            self.applyHorizontalPosition(
                                to: scrollView,
                                initialHorizontalOffset: initialHorizontalOffset,
                                jumpToken: jumpToken,
                                coordinator: coordinator
                            )
                            return
                        }
                        candidate = view.superview
                    }
                }
            }

            private func applyHorizontalPosition(
                to scrollView: UIScrollView,
                initialHorizontalOffset: CGFloat?,
                jumpToken: Int,
                coordinator: Coordinator
            ) {
                guard let initialHorizontalOffset else { return }

                let shouldAnimate: Bool
                if !coordinator.didApplyInitialOffset {
                    coordinator.didApplyInitialOffset = true
                    coordinator.appliedJumpToken = jumpToken
                    shouldAnimate = false
                } else {
                    guard coordinator.appliedJumpToken != jumpToken else { return }
                    coordinator.appliedJumpToken = jumpToken
                    shouldAnimate = true
                }

                scrollView.layoutIfNeeded()
                let maximumX = max(
                    -scrollView.adjustedContentInset.left,
                    scrollView.contentSize.width - scrollView.bounds.width
                        + scrollView.adjustedContentInset.right
                )
                let targetX = min(max(0, initialHorizontalOffset), maximumX)
                scrollView.setContentOffset(
                    CGPoint(x: targetX, y: scrollView.contentOffset.y),
                    animated: shouldAnimate
                )
            }
        }
    }
#endif

// MARK: - Scroller

/// Lays out the frozen panes (corner, ruler, channel column) beside the single
/// scrollable grid. The same layout serves every platform: touch and pointer
/// drag the grid, tvOS moves it by focus, and the frozen column sits *beside*
/// the grid so a focused programme is never hidden behind it.
private struct EPGGridScroller: View {
    let rows: [EPGChannelRow]
    let timeline: EPGTimeline
    let onPlay: (LiveStream) -> Void
    var onNearEnd: () -> Void = {}

    private let metrics = EPGMetrics.current
    private let now = Date()

    @State private var sync = EPGScrollSync()
    @State private var clock = EPGGuideClock()
    @State private var selection: EPGSelection?
    @State private var jumpToken = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header: corner + time ruler. Touch/pointer get a jump-to-now
            // button in the corner; tvOS auto-scrolls to now on appear and has
            // no use for a corner button it can't easily reach, so the corner
            // is left empty there.
            HStack(spacing: 0) {
                corner
                    .frame(width: metrics.channelColumnWidth, height: metrics.headerHeight)

                EPGRulerStrip(timeline: timeline, metrics: metrics, now: now, sync: sync)
            }
            .frame(height: metrics.headerHeight)

            #if !os(tvOS)
                Divider()
            #endif

            // Body: frozen channel column + scrollable programme grid.
            HStack(spacing: 0) {
                EPGFrozenColumn(rows: rows, metrics: metrics, sync: sync)

                EPGGrid(
                    rows: rows,
                    timeline: timeline,
                    metrics: metrics,
                    now: now,
                    sync: sync,
                    jumpToken: jumpToken,
                    nowTarget: nowScrollTarget,
                    onPlay: { row, _ in onPlay(row.stream) },
                    onShowDetails: { row, cell in
                        selection = EPGSelection(id: cell.id, stream: row.stream, cell: cell)
                    },
                    onNearEnd: onNearEnd
                )
            }
        }
        #if !os(tvOS)
        .background(.background)
        #endif
        .environment(\.epgGuideClock, clock)
        .task {
            while !Task.isCancelled {
                let seconds = Calendar.current.component(.second, from: Date())
                do {
                    try await Task.sleep(for: .seconds(max(1, 60 - seconds)))
                } catch {
                    return
                }
                clock.now = Date()
            }
        }
        .sheet(item: $selection) { selection in
            EPGProgramDetailView(
                stream: selection.stream,
                cell: selection.cell,
                now: now,
                onPlay: { onPlay(selection.stream) }
            )
        }
    }

    /// Scroll offset that places "now" just inside the leading edge of the grid.
    private var nowScrollTarget: CGFloat {
        max(0, timeline.x(for: now) - 12)
    }

    @ViewBuilder
    private var corner: some View {
        #if os(tvOS)
            Color.clear
        #else
            Button {
                jumpToken += 1
            } label: {
                Label("Now", systemImage: "smallcircle.filled.circle")
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(ThemeManager.shared.colors.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .trailing) { Rectangle().fill(.quaternary).frame(width: 1) }
        #endif
    }
}

// MARK: - Ruler strip

/// The time ruler, shifted to mirror the grid's horizontal offset. Observes the
/// shared sync so only its offset updates while scrolling — the ruler's own
/// content is built once.
private struct EPGRulerStrip: View {
    let timeline: EPGTimeline
    let metrics: EPGMetrics
    let now: Date
    let sync: EPGScrollSync

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: metrics.headerHeight)
            .overlay(alignment: .leading) {
                ZStack(alignment: .topLeading) {
                    EPGTimeRuler(timeline: timeline, metrics: metrics)
                    nowPill.offset(x: timeline.x(for: now))
                }
                .frame(width: timeline.totalWidth, alignment: .leading)
                .offset(x: -sync.horizontalOffset)
            }
            .clipped()
    }

    private var nowPill: some View {
        Text("Now")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.red))
            .fixedSize()
            .alignmentGuide(.leading) { $0.width / 2 }
    }
}

// MARK: - Frozen column

/// The channel column, shifted to mirror the grid's vertical offset. Built once;
/// only the offset modifier changes as the grid scrolls.
private struct EPGFrozenColumn: View {
    let rows: [EPGChannelRow]
    let metrics: EPGMetrics
    let sync: EPGScrollSync

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .frame(width: metrics.channelColumnWidth)
                .overlay(alignment: .top) {
                    #if os(tvOS)
                        SyncedColumnCells(rows: rows, metrics: metrics, scrollY: sync.verticalOffset)
                    #else
                        // Window only the rows near the viewport. A `LazyVStack`
                        // shifted by `.offset` never realizes off-screen cells, and
                        // SwiftUI `Image(uiImage:)` draws blank in that layout on iOS.
                        WindowedColumnCells(
                            rows: rows,
                            metrics: metrics,
                            scrollY: sync.verticalOffset,
                            viewportHeight: geo.size.height
                        )
                    #endif
                }
                .clipped()
        }
        .frame(width: metrics.channelColumnWidth)
        #if !os(tvOS)
            // The channel cards on tvOS already read as a separate rail, so
            // a vertical rule would only add visual weight.
            .overlay(alignment: .trailing) { Rectangle().fill(.quaternary).frame(width: 1) }
        #endif
    }

    /// tvOS: mirror the grid's vertical offset by scrolling, not transforming,
    /// so `LazyVStack` still realizes the rows in view.
    private struct SyncedColumnCells: View {
        let rows: [EPGChannelRow]
        let metrics: EPGMetrics
        let scrollY: CGFloat

        @State private var position = ScrollPosition()

        var body: some View {
            ScrollView(.vertical) {
                LazyVStack(spacing: metrics.rowSpacing) {
                    ForEach(rows) { row in
                        EPGChannelCell(row: row, metrics: metrics)
                            .id(row.id)
                    }
                }
            }
            .scrollDisabled(true)
            .scrollPosition($position)
            .onChange(of: scrollY) { _, newY in
                position.scrollTo(y: max(0, newY))
            }
        }
    }

    /// iOS / macOS: render a small band of channel cells and slide them with the
    /// grid. Avoids both eager 500-row stacks and broken lazy realization.
    private struct WindowedColumnCells: View {
        let rows: [EPGChannelRow]
        let metrics: EPGMetrics
        let scrollY: CGFloat
        let viewportHeight: CGFloat

        private var rowStride: CGFloat {
            metrics.rowHeight + metrics.rowSpacing
        }

        private var totalHeight: CGFloat {
            guard !rows.isEmpty else { return 0 }
            return CGFloat(rows.count) * metrics.rowHeight + CGFloat(rows.count - 1) * metrics.rowSpacing
        }

        private var startIndex: Int {
            guard rowStride > 0 else { return 0 }
            // Retain two rows above the viewport. Replacing the first visible
            // channel exactly as it crossed the top edge caused a visible pop
            // and extra image work on every row boundary during a fast swipe.
            return max(0, min(rows.count, Int(floor(scrollY / rowStride)) - 2))
        }

        private var endIndex: Int {
            guard rowStride > 0 else { return rows.count }
            let visibleCount = Int(ceil(viewportHeight / rowStride)) + 6
            return min(rows.count, startIndex + visibleCount)
        }

        var body: some View {
            VStack(spacing: metrics.rowSpacing) {
                ForEach(Array(rows[startIndex ..< endIndex])) { row in
                    EPGChannelCell(row: row, metrics: metrics)
                        .id(row.id)
                }
            }
            .padding(.top, CGFloat(startIndex) * rowStride)
            .frame(width: metrics.channelColumnWidth, height: totalHeight, alignment: .top)
            .offset(y: -scrollY)
        }
    }
}

// MARK: - Grid

/// The single scrollable surface. Owns its scroll position (used only for
/// programmatic jump-to-now) and publishes its offset to the shared sync. Its
/// programme rows live in a separate child so the per-frame scroll-position
/// write-back never rebuilds them.
private struct EPGGrid: View {
    let rows: [EPGChannelRow]
    let timeline: EPGTimeline
    let metrics: EPGMetrics
    let now: Date
    let sync: EPGScrollSync
    let jumpToken: Int
    let nowTarget: CGFloat
    let onPlay: (EPGChannelRow, EPGProgramCell) -> Void
    let onShowDetails: (EPGChannelRow, EPGProgramCell) -> Void
    var onNearEnd: () -> Void = {}

    #if !os(iOS)
        @State private var position = ScrollPosition()
        @State private var didInitialScroll = false
    #endif
    /// A combined horizontal+vertical ScrollView centers content that is shorter
    /// than the viewport. The frozen channel column pins its cells to the top, so
    /// without this the two panes drift apart when a category has only a few
    /// channels. Pinning the rows to at least the viewport height (top-aligned)
    /// keeps them level on every platform.
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            EPGRows(
                rows: rows,
                timeline: timeline,
                metrics: metrics,
                now: now,
                onPlay: onPlay,
                onShowDetails: onShowDetails,
                onNearEnd: onNearEnd
            )
            .frame(minHeight: viewportHeight, alignment: .topLeading)
            #if os(iOS)
                .background {
                    EPGScrollDirectionLock(
                        initialHorizontalOffset: nowTarget,
                        jumpToken: jumpToken
                    )
                }
            #endif
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewportHeight = geo.size.height }
                    .onChange(of: geo.size.height) { viewportHeight = $1 }
            }
        }
        #if !os(iOS)
            .scrollPosition($position)
        #endif
        .onScrollGeometryChange(for: CGPoint.self) { $0.contentOffset } action: { _, new in
            let horizontal = max(0, new.x)
            let vertical = max(0, new.y)
            if sync.horizontalOffset != horizontal {
                sync.horizontalOffset = horizontal
            }
            if sync.verticalOffset != vertical {
                sync.verticalOffset = vertical
            }
        }
        #if os(tvOS)
        .focusSection()
        #endif
        #if !os(iOS)
            .onAppear {
                guard !didInitialScroll else { return }
                didInitialScroll = true
                position.scrollTo(x: nowTarget)
            }
            .onChange(of: jumpToken) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    position.scrollTo(x: nowTarget)
                }
            }
        #endif
    }
}

/// The programme rows plus the now line. Free of any scroll-offset dependency,
/// so it builds once and lazily loads rows as they scroll into view.
private struct EPGRows: View {
    let rows: [EPGChannelRow]
    let timeline: EPGTimeline
    let metrics: EPGMetrics
    let now: Date
    let onPlay: (EPGChannelRow, EPGProgramCell) -> Void
    let onShowDetails: (EPGChannelRow, EPGProgramCell) -> Void
    var onNearEnd: () -> Void = {}

    private var contentHeight: CGFloat {
        guard !rows.isEmpty else { return 0 }
        return CGFloat(rows.count) * metrics.rowHeight + CGFloat(rows.count - 1) * metrics.rowSpacing
    }

    var body: some View {
        LazyVStack(spacing: metrics.rowSpacing) {
            ForEach(rows) { row in
                EPGProgramStrip(
                    row: row,
                    timeline: timeline,
                    metrics: metrics,
                    now: now,
                    contentWidth: timeline.totalWidth,
                    onPlay: { cell in onPlay(row, cell) },
                    onShowDetails: { cell in onShowDetails(row, cell) }
                )
                .onAppear {
                    if row.id == rows.last?.id {
                        onNearEnd()
                    }
                }
            }
        }
        .frame(width: timeline.totalWidth, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            TimelineView(.everyMinute) { context in
                EPGNowIndicator(height: contentHeight)
                    .offset(x: timeline.x(for: context.date) - 4.5)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Programme strip

/// A single channel's row of programme blocks. Programmes are buttons; gaps are
/// inert. A quick click plays the channel; programme details open via long-press
/// on tvOS or context menu on iOS/macOS.
private struct EPGProgramStrip: View {
    let row: EPGChannelRow
    let timeline: EPGTimeline
    let metrics: EPGMetrics
    let now: Date
    /// The full timeline width. Pinned on the lazy stack so the row reserves its
    /// whole horizontal extent up front — the scroll region and the "now" line
    /// stay correct even before trailing (off-screen) blocks are realized.
    let contentWidth: CGFloat
    let onPlay: (EPGProgramCell) -> Void
    let onShowDetails: (EPGProgramCell) -> Void

    var body: some View {
        // Place every block from its timestamp instead of accumulating the
        // measured widths of all preceding blocks. tvOS can temporarily report
        // estimated LazyHStack widths while focus realizes off-screen buttons;
        // that shifted entire rows away from the ruler, so the live overlay
        // appeared on a block that did not intersect the red Now line.
        ZStack(alignment: .topLeading) {
            programmeCells
        }
        .frame(width: contentWidth, height: metrics.rowHeight, alignment: .leading)
    }

    @ViewBuilder
    private var programmeCells: some View {
        ForEach(row.cells) { cell in
            if cell.isGap {
                // Gap slots stay playable so a channel without guide data can
                // still be selected. They have no programme detail action.
                Button {
                    onPlay(cell)
                } label: {
                    Color.clear.frame(width: cell.width, height: metrics.rowHeight)
                }
                .buttonStyle(EPGBlockButtonStyle(cell: cell, metrics: metrics, now: now))
                .offset(x: timeline.x(for: cell.start))
                .accessibilityLabel(Text(row.name))
                .accessibilityHint(Text("No programme information"))
            } else {
                Button {
                    onPlay(cell)
                } label: {
                    Color.clear.frame(width: cell.width, height: metrics.rowHeight)
                }
                .buttonStyle(EPGBlockButtonStyle(cell: cell, metrics: metrics, now: now))
                .offset(x: timeline.x(for: cell.start))
                #if os(tvOS)
                    .onLongPressGesture(minimumDuration: 0.4) {
                        onShowDetails(cell)
                    }
                #else
                    .contextMenu {
                        Button("Show Details") { onShowDetails(cell) }
                    }
                #endif
                .accessibilityLabel(Text(cell.title))
                .accessibilityHint(Text("\(cell.start, format: .dateTime.hour().minute()) to \(cell.end, format: .dateTime.hour().minute()) on \(row.name)"))
                .accessibilityAction(named: Text("Show Details")) { onShowDetails(cell) }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("EPG Guide") {
        EPGGuidePreviewHarness()
    }

    /// Seeds an in-memory store with channels and listings around "now" so the
    /// grid can be exercised in the canvas without a live playlist.
    private struct EPGGuidePreviewHarness: View {
        private let container: ModelContainer
        private let category: Category

        init() {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container: ModelContainer
            do {
                container = try ModelContainer(
                    for: Playlist.self, Category.self, LiveStream.self, EPGListing.self,
                    configurations: config
                )
            } catch {
                assertionFailure("Failed to create EPG guide preview container: \(error)")
                fatalError("Failed to create EPG guide preview container")
            }
            let ctx = container.mainContext

            let playlist = Playlist(name: "Preview", serverURL: "http://example.com", username: "u", password: "p")
            ctx.insert(playlist)
            let category = Category(apiId: "20", name: "News", parentId: 0, type: .live, playlist: playlist)
            ctx.insert(category)

            let names = ["BBC One", "CNN International", "HBO", "Sky Sports", "Discovery", "Nat Geo", "ESPN", "ITV"]
            let titles = ["The Evening News", "Morning Show", "Wild Documentary", "Live Football", "Movie Night", "Talk of the Town"]
            let now = Date()
            let windowStart = now.addingTimeInterval(-3600)
            let windowEnd = now.addingTimeInterval(6 * 3600)

            for (index, name) in names.enumerated() {
                let channelId = "chan-\(index)"
                let stream = LiveStream(
                    id: "\(playlist.id.uuidString)-live-\(index)",
                    streamId: 100 + index,
                    name: name,
                    epgChannelId: channelId,
                    tvArchive: index % 3 == 0 ? 1 : 0,
                    tvArchiveDuration: 7,
                    num: index,
                    categoryId: category.id
                )
                ctx.insert(stream)

                var cursor = windowStart.addingTimeInterval(Double(index % 3) * 600) // stagger starts
                var slot = index
                while cursor < windowEnd {
                    let duration = TimeInterval([1800, 2700, 3600][slot % 3])
                    let end = cursor.addingTimeInterval(duration)
                    ctx.insert(EPGListing(
                        id: "\(channelId)-\(slot)",
                        channelId: channelId,
                        title: titles[slot % titles.count],
                        listingDescription: "A sample programme synopsis used for preview purposes only.",
                        start: cursor,
                        end: end
                    ))
                    cursor = end
                    slot += 1
                }
            }
            try? ctx.save()

            self.container = container
            self.category = category
        }

        var body: some View {
            EPGGuideView(
                scope: .category(category.id),
                playlistPrefix: "",
                sort: .playlist,
                sectionToken: category.id,
                epgCache: LiveTVSectionEPGCache()
            ) { _ in }
                .modelContainer(container)
                .frame(minHeight: 520)
        }
    }
#endif
