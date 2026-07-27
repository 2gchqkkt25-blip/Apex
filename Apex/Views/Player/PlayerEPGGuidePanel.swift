//
//  PlayerEPGGuidePanel.swift
//  Apex
//
//  Compact multi-channel EPG timeline for the in-player Guide overlay. Mirrors
//  the main Live TV guide (`EPGGuideView`): frozen channel column + programme
//  strips in a single bidirectional ScrollView, with focus-driven scrolling on
//  tvOS.
//

import Combine
import SwiftData
import SwiftUI

/// Compact programme guide shown over live playback. Tapping a channel or a
/// programme switches to that channel via `onSelect`.
struct PlayerEPGGuidePanel: View {
    let media: PlayableMedia
    var onSelect: (PlayableMedia) -> Void
    var onClose: (() -> Void)?
    #if os(tvOS)
        var focus: FocusState<TVPlayerFocus?>.Binding
    #endif

    @Environment(\.modelContext) private var modelContext
    @AppStorage(SortStorageKey.liveContent) private var contentSortRaw: String = ContentSortOption.playlist.rawValue

    @State private var channels: [LiveStream] = []
    @State private var programsByChannel: [String: [EPGProgram]] = [:]
    @State private var now = Date()
    @State private var epgSync = EPGSyncService.shared
    @State private var scrollSync = EPGScrollSync()
    @State private var scrollPosition = ScrollPosition()
    @State private var didScrollToNow = false

    private let metrics = EPGMetrics.playerOverlay
    private let panelHeight: CGFloat = {
        #if os(tvOS)
            480
        #else
            280
        #endif
    }()

    private var timeline: EPGTimeline {
        EPGTimeline.live(
            now: now,
            pointsPerMinute: metrics.pointsPerMinute,
            hoursBehind: 1,
            hoursAhead: 3
        )
    }

    private var rows: [EPGChannelRow] {
        EPGGridBuilder.rows(
            streams: channels,
            programsByChannel: programsByChannel,
            timeline: timeline
        )
    }

    private var nowScrollTarget: CGFloat {
        max(0, timeline.x(for: now) - 24)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if channels.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                guideGrid
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: panelHeight)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.72))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .preferredColorScheme(.dark)
        .task(id: media.id) {
            didScrollToNow = false
            await reload()
        }
        .onChange(of: epgSync.refreshGeneration) {
            Task { await reload(force: true) }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            now = date
        }
    }

    private var header: some View {
        HStack {
            Label("Guide", systemImage: "list.bullet.rectangle")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Text(now, format: .dateTime.hour().minute())
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
            #if !os(tvOS)
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close guide")
                }
            #endif
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Same layout idea as `EPGGuideView`: frozen channel column beside a
    /// single bidirectional programme ScrollView (not nested scrollers).
    private var guideGrid: some View {
        let timeline = self.timeline
        let displayRows = rows
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: metrics.channelColumnWidth, height: metrics.headerHeight)
                playerRulerStrip(timeline: timeline)
            }
            .frame(height: metrics.headerHeight)

            HStack(spacing: 0) {
                playerChannelColumn(rows: displayRows)
                playerProgrammeGrid(rows: displayRows, timeline: timeline)
            }
        }
        #if os(tvOS)
            .focusSection()
        #endif
    }

    private func playerRulerStrip(timeline: EPGTimeline) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: metrics.headerHeight)
            .overlay(alignment: .leading) {
                EPGTimeRuler(timeline: timeline, metrics: metrics)
                    .foregroundStyle(.white)
                    .frame(width: timeline.totalWidth, alignment: .leading)
                    .offset(x: -scrollSync.offset.x)
            }
            .clipped()
    }

    private func playerChannelColumn(rows: [EPGChannelRow]) -> some View {
        Color.clear
            .frame(width: metrics.channelColumnWidth)
            .overlay(alignment: .top) {
                VStack(spacing: metrics.rowSpacing) {
                    ForEach(rows) { row in
                        channelCellButton(row)
                    }
                }
                .offset(y: -scrollSync.offset.y)
            }
            .clipped()
            .frame(width: metrics.channelColumnWidth)
    }

    private func channelCellButton(_ row: EPGChannelRow) -> some View {
        Button {
            select(row.stream)
        } label: {
            HStack(spacing: 8) {
                ChannelLogoView(
                    url: row.logoURL,
                    size: metrics.rowHeight * 0.55,
                    cornerRadius: 6,
                    contentPadding: 2
                )
                Text(row.name)
                    #if os(tvOS)
                        .font(.system(size: 22, weight: .semibold))
                    #else
                        .font(.caption.weight(.semibold))
                    #endif
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .frame(width: metrics.channelColumnWidth, height: metrics.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                row.stream.id == currentChannelID
                    ? Color.white.opacity(0.14)
                    : Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        #if os(tvOS)
            .focused(focus, equals: .guideChannel(row.id))
        #endif
        .disabled(row.stream.id == currentChannelID)
        .accessibilityLabel(Text(row.name))
        .accessibilityHint(Text("Switch channel"))
    }

    private func playerProgrammeGrid(rows: [EPGChannelRow], timeline: EPGTimeline) -> some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: metrics.rowSpacing) {
                ForEach(rows) { row in
                    programmeStrip(row, timeline: timeline)
                }
            }
            .frame(width: timeline.totalWidth, alignment: .topLeading)
            .overlay(alignment: .topLeading) {
                EPGNowIndicator(
                    height: CGFloat(rows.count) * metrics.rowHeight
                        + CGFloat(max(rows.count - 1, 0)) * metrics.rowSpacing
                )
                .offset(x: timeline.x(for: now) - 1)
                .allowsHitTesting(false)
            }
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGPoint.self) { $0.contentOffset } action: { _, new in
            scrollSync.offset = CGPoint(x: max(0, new.x), y: max(0, new.y))
        }
        #if os(tvOS)
            .focusSection()
        #endif
        .onAppear {
            guard !didScrollToNow else { return }
            didScrollToNow = true
            scrollPosition.scrollTo(x: nowScrollTarget)
        }
        .onChange(of: channels.map(\.id)) {
            didScrollToNow = false
            scrollPosition.scrollTo(x: nowScrollTarget)
            didScrollToNow = true
        }
    }

    private func programmeStrip(_ row: EPGChannelRow, timeline: EPGTimeline) -> some View {
        LazyHStack(spacing: 0) {
            ForEach(row.cells) { cell in
                Button {
                    select(row.stream)
                } label: {
                    Color.clear
                        .frame(width: cell.width, height: metrics.rowHeight)
                }
                .buttonStyle(EPGBlockButtonStyle(cell: cell, metrics: metrics, now: now))
                #if os(tvOS)
                    .focused(focus, equals: .guideProgram(cell.id))
                #endif
                .disabled(row.stream.id == currentChannelID)
                .accessibilityLabel(Text(cell.isGap ? row.name : cell.title))
                .accessibilityHint(Text("Switch channel"))
            }
        }
        .frame(width: timeline.totalWidth, height: metrics.rowHeight, alignment: .leading)
    }

    private var currentChannelID: String? {
        if case let .live(id) = media.contentRef { return id }
        return nil
    }

    private func select(_ stream: LiveStream) {
        guard stream.id != currentChannelID else { return }
        guard let playlist = LiveChannelNavigator.playlist(for: stream, in: modelContext),
              let newMedia = PlayableMedia.from(stream: stream, playlist: playlist) else { return }
        onSelect(newMedia)
    }

    @MainActor
    private func reload(force: Bool = false) async {
        let sort = ContentSortOption(rawValue: contentSortRaw) ?? .playlist
        let loadedChannels = LiveChannelNavigator.surfChannels(
            for: media,
            sort: sort,
            scope: LiveChannelNavigator.activeSurfScope,
            in: modelContext
        )
        channels = loadedChannels
        guard !loadedChannels.isEmpty else { return }

        let playlist = loadedChannels.first.flatMap {
            LiveChannelNavigator.playlist(for: $0, in: modelContext)
        }
        let result = await EPGBrowseLoader.load(
            container: modelContext.container,
            channels: loadedChannels,
            playlist: playlist
        )
        guard !Task.isCancelled else { return }
        var merged = force ? [:] : programsByChannel
        for (key, value) in result.programs {
            merged[key] = value
        }
        programsByChannel = merged
        now = Date()
    }
}
