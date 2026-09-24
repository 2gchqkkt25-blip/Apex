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
#if os(iOS) || os(tvOS)
    import UIKit
#endif

struct EPGGuideView: View {
    let scope: LiveChannelScope
    let playlistPrefix: String
    let playlist: Playlist?
    let sectionToken: String
    @Bindable var epgCache: LiveTVSectionEPGCache
    /// Bumped when fullscreen playback ends. The guide stays mounted under the
    /// player, so without this it restores the scroll position from when the
    /// channel was tuned instead of the current time.
    var playbackReturnToken: Int = 0
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
        playbackReturnToken: Int = 0,
        onPlay: @escaping (LiveStream) -> Void
    ) {
        self.scope = scope
        self.playlistPrefix = playlistPrefix
        self.playlist = playlist
        self.sectionToken = sectionToken
        _epgCache = Bindable(epgCache)
        self.playbackReturnToken = playbackReturnToken
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
                playbackReturnToken: playbackReturnToken,
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

                // First presentation only. Returning from the player does not
                // run this — the guide stays mounted under the cover — so that
                // path uses `playbackReturnToken` instead.
                timeline = EPGTimeline.live(
                    now: Date(),
                    pointsPerMinute: EPGMetrics.current.pointsPerMinute,
                    hoursBehind: 6,
                    hoursAhead: 12
                )
            }
            .task(id: sectionToken) {
                epgCache.activate(section: sectionToken)
                await loadGuide(for: visible)
            }
            .onChange(of: sectionToken) {
                visibleCount = LiveChannelQuery.pageSize
            }
            .onChange(of: playbackReturnToken) {
                timeline = EPGTimeline.live(
                    now: Date(),
                    pointsPerMinute: EPGMetrics.current.pointsPerMinute,
                    hoursBehind: 6,
                    hoursAhead: 12
                )
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

#if os(tvOS)
    /// Pins `clipsToBounds` on the guide's scroll view. SwiftUI turns it off
    /// so a focused programme can scale past the cell, and the unclipped
    /// cells then draw across the channel column and the time ruler.
    private struct EPGScrollClipEnforcer: UIViewRepresentable {
        func makeUIView(context _: Context) -> UIView {
            ProbeView()
        }

        func updateUIView(_ view: UIView, context _: Context) {
            (view as? ProbeView)?.clipNearestScrollView()
        }

        private final class ProbeView: UIView {
            func clipNearestScrollView() {
                Task { @MainActor [weak self] in
                    await Task.yield()
                    guard let self else { return }
                    var candidate = superview
                    while let view = candidate {
                        if let scrollView = view as? UIScrollView {
                            scrollView.clipsToBounds = true
                            return
                        }
                        candidate = view.superview
                    }
                }
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
    var playbackReturnToken: Int = 0
    let onPlay: (LiveStream) -> Void
    var onNearEnd: () -> Void = {}

    private let metrics = EPGMetrics.current
    @State private var now = Date()

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
            #if os(tvOS)
                .background(ThemeManager.shared.colors.background)
            #endif
            // Painted above the grid so a scrolling row can't cover the ruler.
            .zIndex(1)

            #if !os(tvOS)
                Divider()
            #endif

            // Body: frozen channel column + scrollable programme grid.
            // Top alignment keeps channel cells level with programme rows.
            // The default centre alignment let the taller tvOS column hang
            // over the ruler while the grid stayed pinned to the top.
            HStack(alignment: .top, spacing: 0) {
                #if !os(tvOS)
                    // tvOS draws the channel label inside each programme row so
                    // it scrolls vertically with that row. A second column
                    // synced by offset drifted off the programmes.
                    EPGFrozenColumn(rows: rows, metrics: metrics, sync: sync)
                        .zIndex(1)
                #endif

                EPGGrid(
                    rows: rows,
                    timeline: timeline,
                    metrics: metrics,
                    now: now,
                    playbackReturnToken: playbackReturnToken,
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
            .clipped()
        }
        #if !os(tvOS)
        .background(.background)
        #endif
        .environment(\.epgGuideClock, clock)
        .onChange(of: playbackReturnToken) {
            reanchorToNow()
            // Focus restoration after the player cover can scroll back to the
            // programme that was selected. A second pass lands on the clock
            // once that restoration has finished.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                reanchorToNow()
            }
        }
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

    private func reanchorToNow() {
        now = Date()
        jumpToken += 1
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
        #if os(tvOS)
            // tvOS: no GeometryReader — it creates an opaque layout boundary
            // that hides child frames from the focus engine, so vertical focus
            // moves don't land on the correct channel cell even though the
            // padding-based windowing renders them at the right position.
            // The grid's own viewport-height tracking already constrains the
            // column; we just need a fixed frame here.
            SyncedColumnCells(rows: rows, metrics: metrics, sync: sync)
                .frame(maxHeight: .infinity, alignment: .top)
                .frame(width: metrics.channelColumnWidth)
                .clipped()
        #else
            GeometryReader { geo in
                Color.clear
                    .frame(width: metrics.channelColumnWidth)
                    .overlay(alignment: .top) {
                        // Window only the rows near the viewport. A `LazyVStack`
                        // shifted by `.offset` never realizes off-screen cells, and
                        // SwiftUI `Image(uiImage:)` draws blank in that layout on iOS.
                        WindowedColumnCells(
                            rows: rows,
                            metrics: metrics,
                            scrollY: sync.verticalOffset,
                            viewportHeight: geo.size.height
                        )
                    }
                    .clipped()
            }
            .frame(width: metrics.channelColumnWidth)
            // The channel cards on tvOS already read as a separate rail, so
            // a vertical rule would only add visual weight.
            .overlay(alignment: .trailing) { Rectangle().fill(.quaternary).frame(width: 1) }
        #endif
    }

    /// tvOS: render only the channel cells near the current scroll position
    /// using a plain VStack with computed windowing. The previous approaches
    /// both failed on tvOS: a second ScrollView created a competing focus
    /// coordinate space that desynced from the grid, and GeometryReader +
    /// .offset broke focus-engine layout reporting because the transformed
    /// coordinates were invisible to the focus system. This version renders
    /// a small window of cells pinned to the top with padding that matches
    /// the grid's scroll position, keeping cells in the same focus tree
    /// while avoiding GeometryReader entirely.
    ///
    /// Crucially, this view observes `EPGScrollSync` directly rather than
    /// receiving `scrollY` as a value parameter. Passing a CGFloat snapshot
    /// breaks @Observable tracking on tvOS — the child never re-renders when
    /// the grid scrolls because SwiftUI only tracks property access inside
    /// the observing view's own body. Reading `sync.verticalOffset` here
    /// ensures every scroll update triggers a re-layout.
    private struct SyncedColumnCells: View {
        let rows: [EPGChannelRow]
        let metrics: EPGMetrics
        let sync: EPGScrollSync

        private var rowStride: CGFloat {
            metrics.rowHeight + metrics.rowSpacing
        }

        private var scrollY: CGFloat {
            sync.verticalOffset
        }

        private var startIndex: Int {
            guard rowStride > 0 else { return 0 }
            // Keep two rows above the viewport so focus can move up without
            // hitting an unrealized cell at the top edge.
            return max(0, min(rows.count, Int(floor(max(0, scrollY) / rowStride)) - 2))
        }

        private var visibleRows: ArraySlice<EPGChannelRow> {
            guard rowStride > 0, !rows.isEmpty else { return rows.prefix(0) }
            let start = startIndex
            // Render enough rows to fill a 1080p viewport plus buffer for
            // focus movement and scroll momentum.
            let visibleCount = 14
            let end = min(rows.count, start + visibleCount)
            return rows[start ..< end]
        }

        var body: some View {
            VStack(spacing: metrics.rowSpacing) {
                ForEach(Array(visibleRows)) { row in
                    EPGChannelCell(row: row, metrics: metrics)
                        .id(row.id)
                        .frame(height: metrics.rowHeight)
                }
            }
            .padding(.top, CGFloat(startIndex) * rowStride - max(0, scrollY))
            .frame(width: metrics.channelColumnWidth, alignment: .top)
            .clipped()
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
    var playbackReturnToken: Int = 0
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
                playbackReturnToken: playbackReturnToken,
                sync: sync,
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
            #elseif os(tvOS)
                // tvOS leaves the guide scroll view unclipped so focus can
                // lift. Programme cells then paint over the channel column
                // and the time ruler while the grid moves. Force clipping.
                .background { EPGScrollClipEnforcer() }
            #endif
        }
        .clipped()
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
        .onScrollGeometryChange(for: CGPoint.self) { geo in
            // visibleRect is the content under the viewport. contentOffset
            // lags that on tvOS once safe-area insets are applied, which
            // slid the frozen column off the programme rows.
            CGPoint(x: geo.visibleRect.minX, y: geo.visibleRect.minY)
        } action: { _, new in
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
                // Always scroll to "now" on appear. The parent refreshes
                // `timeline` in its own onAppear when returning from playback,
                // which changes `nowTarget`; guarding with a one-shot flag
                // would leave the grid anchored at the stale selection time
                // after watching a long movie. SwiftUI preserves this child's
                // @State across navigation, so resetting here is safe and
                // keeps every platform aligned with wall-clock time.
                didInitialScroll = true
                position.scrollTo(x: nowTarget)
            }
            .onChange(of: jumpToken) {
                let target = max(0, timeline.x(for: Date()) - 12)
                withAnimation(.easeInOut(duration: 0.4)) {
                    position.scrollTo(x: target)
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
    var playbackReturnToken: Int = 0
    let sync: EPGScrollSync
    let onPlay: (EPGChannelRow, EPGProgramCell) -> Void
    let onShowDetails: (EPGChannelRow, EPGProgramCell) -> Void
    var onNearEnd: () -> Void = {}

    #if os(tvOS)
        /// Time that vertical moves should keep. A live programme anchors on
        /// "now", so the next channel focuses what is airing there rather than
        /// the block that happens to sit under a longer box.
        @State private var verticalAnchor = Date()
        @State private var focusedRowID: String?
        @FocusState private var focusedCellID: String?
    #endif

    /// tvOS keeps the channel label inside the scrolling row. The label is
    /// shifted back by the horizontal offset so it stays under the corner.
    private var channelInset: CGFloat {
        #if os(tvOS)
            metrics.channelColumnWidth
        #else
            0
        #endif
    }

    private var contentHeight: CGFloat {
        guard !rows.isEmpty else { return 0 }
        return CGFloat(rows.count) * metrics.rowHeight + CGFloat(rows.count - 1) * metrics.rowSpacing
    }

    var body: some View {
        LazyVStack(spacing: metrics.rowSpacing) {
            ForEach(rows) { row in
                rowView(row)
                    .onAppear {
                        if row.id == rows.last?.id {
                            onNearEnd()
                        }
                    }
            }
        }
        .frame(width: timeline.totalWidth + channelInset, alignment: .topLeading)
        #if os(tvOS)
            .onChange(of: playbackReturnToken) {
                focusCurrentProgramme()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    focusCurrentProgramme()
                }
            }
            .onChange(of: focusedCellID) { _, id in
                guard let id, let match = locatedCell(id) else { return }
                if focusedRowID != match.row.id {
                    let enteredFromAnotherRow = focusedRowID != nil
                    focusedRowID = match.row.id
                    if enteredFromAnotherRow,
                       let desired = match.row.cells.first(where: { $0.start <= verticalAnchor && verticalAnchor < $0.end }),
                       desired.id != id
                    {
                        focusedCellID = desired.id
                        return
                    }
                }
                let current = Date()
                verticalAnchor = match.cell.isLive(at: current) ? current : match.cell.start
            }
        #endif
        .overlay(alignment: .topLeading) {
            TimelineView(.everyMinute) { context in
                EPGNowIndicator(height: contentHeight)
                    .offset(x: channelInset + timeline.x(for: context.date) - 4.5)
                    .allowsHitTesting(false)
            }
        }
    }

    #if os(tvOS)
        /// Move focus onto whatever is airing on the focused channel at the
        /// current time, so leaving the player does not restore the programme
        /// that was highlighted when playback started.
        private func focusCurrentProgramme() {
            let current = Date()
            verticalAnchor = current
            guard let rowID = focusedRowID,
                  let row = rows.first(where: { $0.id == rowID }),
                  let live = row.cells.first(where: { $0.isLive(at: current) })
            else { return }
            focusedCellID = live.id
        }
    #endif

    @ViewBuilder
    private func rowView(_ row: EPGChannelRow) -> some View {
        #if os(tvOS)
            let target = row.cells.first { $0.start <= verticalAnchor && verticalAnchor < $0.end }?.id
            EPGProgramStrip(
                row: row,
                timeline: timeline,
                metrics: metrics,
                now: now,
                contentWidth: timeline.totalWidth,
                scrollSync: sync,
                verticalAnchor: verticalAnchor,
                focusedCellID: $focusedCellID,
                onPlay: { cell in onPlay(row, cell) },
                onShowDetails: { cell in onShowDetails(row, cell) }
            )
            .focusSection()
            .modifier(EPGDefaultFocus(focused: $focusedCellID, cellID: target))
            .padding(.leading, metrics.channelColumnWidth)
            .overlay(alignment: .topLeading) {
                EPGStickyChannel(row: row, metrics: metrics, sync: sync)
            }
        #else
            EPGProgramStrip(
                row: row,
                timeline: timeline,
                metrics: metrics,
                now: now,
                contentWidth: timeline.totalWidth,
                scrollSync: sync,
                onPlay: { cell in onPlay(row, cell) },
                onShowDetails: { cell in onShowDetails(row, cell) }
            )
        #endif
    }

    #if os(tvOS)
        private func locatedCell(_ id: String) -> (row: EPGChannelRow, cell: EPGProgramCell)? {
            for row in rows {
                if let cell = row.cells.first(where: { $0.id == id }) {
                    return (row, cell)
                }
            }
            return nil
        }
    #endif
}

#if os(tvOS)
    /// Applies `defaultFocus` only when this row has a programme at the anchor
    /// time. Entering the row then lands on that programme.
    private struct EPGDefaultFocus: ViewModifier {
        var focused: FocusState<String?>.Binding
        var cellID: String?

        func body(content: Content) -> some View {
            if let cellID {
                content.defaultFocus(focused, cellID)
            } else {
                content
            }
        }
    }

    /// Channel label that lives on the programme row, so vertical scrolling
    /// cannot separate it from that row. Horizontal scrolling moves the row;
    /// this view shifts back by the same amount and covers the programmes
    /// passing underneath it.
    private struct EPGStickyChannel: View {
        let row: EPGChannelRow
        let metrics: EPGMetrics
        let sync: EPGScrollSync

        var body: some View {
            EPGChannelCell(row: row, metrics: metrics)
                .frame(width: metrics.channelColumnWidth, height: metrics.rowHeight)
                .background {
                    ThemeManager.shared.colors.background
                        .frame(height: metrics.rowHeight + metrics.rowSpacing)
                }
                .offset(x: sync.horizontalOffset)
                .zIndex(1)
        }
    }
#endif

/// Focus target with no system highlight. The programme block draws the
/// selection; the default tvOS button style was adding a second white box.
private struct EPGClearFocusButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .focusEffectDisabled()
    }
}

/// Lays programme blocks out at their timeline position so the focus frame
/// matches the pixels on screen. `.offset` does not do that on tvOS.
private struct EPGProgramTimelineLayout: Layout {
    var origins: [CGFloat]

    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache _: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for index in subviews.indices {
            let subview = subviews[index]
            let size = subview.sizeThatFits(.unspecified)
            let origin = index < origins.count ? origins[index] : 0
            subview.place(
                at: CGPoint(x: bounds.minX + origin, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: bounds.height)
            )
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
    var scrollSync: EPGScrollSync? = nil
    #if os(tvOS)
        /// Time vertical focus should stay aligned with. The focusable slice of
        /// each programme sits on this instant, so a long box cannot pull the
        /// selection onto a later show.
        var verticalAnchor: Date
        var focusedCellID: FocusState<String?>.Binding
    #endif
    let onPlay: (EPGProgramCell) -> Void
    let onShowDetails: (EPGProgramCell) -> Void

    var body: some View {
        // Place every block from its timestamp. `.offset` only moves the
        // drawing; tvOS focus still sees every button stacked at x = 0 and
        // scrolls the guide to that point, so the grid jumps away from the
        // cell on screen. A layout puts the focus frame on the drawn cell.
        EPGProgramTimelineLayout(origins: layoutOrigins) {
            programmeCells
        }
        .frame(width: contentWidth, height: metrics.rowHeight, alignment: .topLeading)
    }

    private var layoutOrigins: [CGFloat] {
        #if os(tvOS)
            row.cells.map { timeline.x(for: $0.start) }
                + row.cells.map { timeline.x(for: focusSlice(for: $0).start) }
        #else
            row.cells.map { timeline.x(for: $0.start) }
        #endif
    }

    #if os(tvOS)
        /// A short focus target on `verticalAnchor`, clamped inside the programme.
        /// The drawn block stays full length; only this slice is focusable, so
        /// moving down stays on the same time.
        private func focusSlice(for cell: EPGProgramCell) -> (start: Date, end: Date) {
            let latestStart = cell.end.addingTimeInterval(-60)
            let start = min(max(verticalAnchor, cell.start), max(cell.start, latestStart))
            let end = min(cell.end, start.addingTimeInterval(30 * 60))
            if end > start {
                return (start, end)
            }
            return (cell.start, cell.end)
        }
    #endif

    @ViewBuilder
    private var programmeCells: some View {
        #if os(tvOS)
            ForEach(row.cells) { cell in
                EPGProgramBlockView(
                    cell: cell,
                    metrics: metrics,
                    now: now,
                    isFocused: focusedCellID.wrappedValue == cell.id,
                    scrollSync: scrollSync,
                    timelineOrigin: timeline.x(for: cell.start)
                )
                .allowsHitTesting(false)
                .scaleEffect(focusedCellID.wrappedValue == cell.id ? 1.04 : 1)
                .animation(.easeOut(duration: 0.18), value: focusedCellID.wrappedValue == cell.id)
            }
            ForEach(row.cells) { cell in
                let slice = focusSlice(for: cell)
                let sliceWidth = timeline.width(from: slice.start, to: slice.end)
                Button {
                    onPlay(cell)
                } label: {
                    Color.clear
                        .frame(width: sliceWidth, height: metrics.rowHeight)
                }
                .buttonStyle(EPGClearFocusButtonStyle())
                .focusEffectDisabled()
                .frame(width: sliceWidth, height: metrics.rowHeight)
                .focused(focusedCellID, equals: cell.id)
                .onLongPressGesture(minimumDuration: 0.4) {
                    if !cell.isGap { onShowDetails(cell) }
                }
                .accessibilityLabel(Text(cell.isGap ? row.name : cell.title))
            }
        #else
            programmeButtons
        #endif
    }

    @ViewBuilder
    private var programmeButtons: some View {
        ForEach(row.cells) { cell in
            if cell.isGap {
                // Gap slots stay playable so a channel without guide data can
                // still be selected. They have no programme detail action.
                Button {
                    onPlay(cell)
                } label: {
                    Color.clear.frame(width: cell.width, height: metrics.rowHeight)
                }
                .buttonStyle(EPGBlockButtonStyle(
                    cell: cell,
                    metrics: metrics,
                    now: now,
                    scrollSync: scrollSync,
                    timelineOrigin: timeline.x(for: cell.start)
                ))
                .frame(width: cell.width, height: metrics.rowHeight, alignment: .leading)
                .accessibilityLabel(Text(row.name))
                .accessibilityHint(Text("No programme information"))
            } else {
                Button {
                    onPlay(cell)
                } label: {
                    Color.clear.frame(width: cell.width, height: metrics.rowHeight)
                }
                .buttonStyle(EPGBlockButtonStyle(
                    cell: cell,
                    metrics: metrics,
                    now: now,
                    scrollSync: scrollSync,
                    timelineOrigin: timeline.x(for: cell.start)
                ))
                .frame(width: cell.width, height: metrics.rowHeight, alignment: .leading)
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
