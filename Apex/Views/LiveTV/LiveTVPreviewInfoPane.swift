//
//  LiveTVPreviewInfoPane.swift
//  Apex
//
//  Channel name, now/next programme, and synopsis for the band beside the
//  Live TV mini preview (Chilli / Really-style). Shared by tvOS and iOS.
//

import SwiftData
import SwiftUI

/// Non-interactive channel + programme caption for the mini-preview row.
struct LiveTVPreviewInfoPane: View {
    let media: PlayableMedia
    @Bindable var epgCache: LiveTVSectionEPGCache
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let stream = liveStream(for: media.contentRef)
            let programs = programs(for: stream)
            let slotEPG = EPGLiveLoader.makeChannelEPG(from: programs, now: now)
            let current = program(matching: slotEPG.current, in: programs)
            let next = program(matching: slotEPG.next, in: programs)

            HStack(alignment: .top, spacing: Metrics.stackSpacing) {
                ChannelLogoView(
                    url: stream?.iconURL ?? media.posterURL,
                    size: Metrics.logoSize,
                    cornerRadius: Metrics.logoCorner,
                    contentPadding: Metrics.logoPadding
                )

                VStack(alignment: .leading, spacing: Metrics.textSpacing) {
                    Text(stream?.name ?? media.title)
                        .font(Metrics.channelFont)
                        .foregroundStyle(Metrics.primaryColor)
                        .lineLimit(1)

                    if let current {
                        Text(current.title)
                            .font(Metrics.programmeFont)
                            .foregroundStyle(Metrics.primaryColor)
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            Text(current.start, style: .time)
                            Text("–")
                            Text(current.end, style: .time)
                            if current.start <= now, now < current.end {
                                Text("· On Now")
                                    .foregroundStyle(.red)
                            }
                        }
                        .font(Metrics.metaFont)
                        .foregroundStyle(Metrics.secondaryColor)

                        if current.start <= now, now < current.end {
                            ProgressView(value: progress(of: current, at: now))
                                .tint(.red)
                                .frame(maxWidth: Metrics.progressMaxWidth)
                        }

                        if !current.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(current.description)
                                .font(Metrics.bodyFont)
                                .foregroundStyle(Metrics.secondaryColor)
                                .lineLimit(Metrics.descriptionLines)
                                .lineSpacing(Metrics.descriptionLineSpacing)
                        }
                    } else if let subtitle = media.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Metrics.bodyFont)
                            .foregroundStyle(Metrics.secondaryColor)
                            .lineLimit(2)
                    } else {
                        Text("Live")
                            .font(Metrics.bodyFont)
                            .foregroundStyle(Metrics.secondaryColor)
                    }

                    if let next {
                        HStack(spacing: 6) {
                            Text("Next:")
                            Text(next.title).lineLimit(1)
                            Text(next.start, style: .time)
                        }
                        .font(Metrics.metaFont)
                        .foregroundStyle(Metrics.tertiaryColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func liveStream(for ref: PlayableMedia.ContentRef) -> LiveStream? {
        guard case let .live(id) = ref else { return nil }
        var descriptor = FetchDescriptor<LiveStream>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func programs(for stream: LiveStream?) -> [EPGProgram] {
        guard let stream else { return [] }
        for key in stream.epgLookupIDs {
            if let programs = epgCache.programsByChannel[key], !programs.isEmpty {
                return programs
            }
        }
        return epgCache.programsByChannel[stream.primaryEPGChannelId] ?? []
    }

    private func program(matching slot: EPGSlot?, in programs: [EPGProgram]) -> EPGProgram? {
        guard let slot else { return nil }
        return programs.first { $0.start == slot.start && $0.end == slot.end }
            ?? programs.first { $0.title == slot.title && $0.start == slot.start }
    }

    private func progress(of program: EPGProgram, at now: Date) -> Double {
        let duration = program.end.timeIntervalSince(program.start)
        guard duration > 0 else { return 0 }
        return min(max(now.timeIntervalSince(program.start) / duration, 0), 1)
    }

    // MARK: - Metrics

    private enum Metrics {
        #if os(tvOS)
            static let stackSpacing: CGFloat = 20
            static let textSpacing: CGFloat = 8
            static let logoSize: CGFloat = 96
            static let logoCorner: CGFloat = 14
            static let logoPadding: CGFloat = 10
            static let progressMaxWidth: CGFloat = 420
            static let descriptionLines = 3
            static let descriptionLineSpacing: CGFloat = 4
            static let channelFont = Font.system(size: 28, weight: .semibold)
            static let programmeFont = Font.system(size: 34, weight: .bold)
            static let metaFont = Font.system(size: 22)
            static let bodyFont = Font.system(size: 24)
            static let primaryColor = Color.white
            static let secondaryColor = Color.white.opacity(0.72)
            static let tertiaryColor = Color.white.opacity(0.55)
        #elseif os(macOS)
            static let stackSpacing: CGFloat = 14
            static let textSpacing: CGFloat = 6
            static let logoSize: CGFloat = 96
            static let logoCorner: CGFloat = 12
            static let logoPadding: CGFloat = 4
            static let progressMaxWidth: CGFloat = 360
            static let descriptionLines = 3
            static let descriptionLineSpacing: CGFloat = 3
            static let channelFont = Font.title3.weight(.semibold)
            static let programmeFont = Font.title2.weight(.bold)
            static let metaFont = Font.callout
            static let bodyFont = Font.callout
            static let primaryColor = Color.primary
            static let secondaryColor = Color.secondary
            static let tertiaryColor = Color.secondary.opacity(0.85)
        #else
            static let stackSpacing: CGFloat = 10
            static let textSpacing: CGFloat = 4
            static let logoSize: CGFloat = 48
            static let logoCorner: CGFloat = 8
            static let logoPadding: CGFloat = 4
            static let progressMaxWidth: CGFloat = 220
            static let descriptionLines = 2
            static let descriptionLineSpacing: CGFloat = 2
            static let channelFont = Font.subheadline.weight(.semibold)
            static let programmeFont = Font.headline.weight(.bold)
            static let metaFont = Font.caption
            static let bodyFont = Font.caption
            static let primaryColor = Color.primary
            static let secondaryColor = Color.secondary
            static let tertiaryColor = Color.secondary.opacity(0.85)
        #endif
    }
}