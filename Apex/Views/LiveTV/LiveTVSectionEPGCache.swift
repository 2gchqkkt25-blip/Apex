//
//  LiveTVSectionEPGCache.swift
//  Apex
//
//  Shared in-memory EPG for a Live TV section. List and guide read the same
//  programme data so toggling views or returning to a category is instant.
//  SwiftData remains the source of truth; this cache survives view recreation.
//

import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class LiveTVSectionEPGCache {
    private struct SectionSnapshot {
        var programsByChannel: [String: [EPGProgram]] = [:]
        var epgByChannel: [String: ChannelEPG] = [:]
    }

    private(set) var programsByChannel: [String: [EPGProgram]] = [:]
    private(set) var epgByChannel: [String: ChannelEPG] = [:]

    private var sections: [String: SectionSnapshot] = [:]
    private var sectionOrder: [String] = []
    private static let sectionLimit = 12
    private(set) var activeSectionToken: String = ""

    func activate(section: String) {
        guard activeSectionToken != section else { return }
        persistActiveSection()
        activeSectionToken = section
        touch(section)
        if let snapshot = sections[section] {
            programsByChannel = snapshot.programsByChannel
            epgByChannel = snapshot.epgByChannel
        } else {
            programsByChannel = [:]
            epgByChannel = [:]
        }
    }

    func merge(
        section: String,
        loaded: (channelEPG: [String: ChannelEPG], programs: [String: [EPGProgram]])
    ) {
        var snapshot = sections[section] ?? SectionSnapshot()
        var changed = false
        for (channelId, programs) in loaded.programs {
            // Skip identical lists so mid-sync / gap-fill refreshes don't rebuild the
            // tvOS guide focus tree for channels that already have this data.
            if snapshot.programsByChannel[channelId] != programs {
                snapshot.programsByChannel[channelId] = programs
                changed = true
            }
        }
        for (channelId, epg) in loaded.channelEPG {
            if snapshot.epgByChannel[channelId] != epg {
                snapshot.epgByChannel[channelId] = epg
                changed = true
            }
        }
        guard changed else { return }
        sections[section] = snapshot
        touch(section)
        if section == activeSectionToken {
            programsByChannel = snapshot.programsByChannel
            epgByChannel = snapshot.epgByChannel
        }
    }

    /// Applies live-API authority without replacing existing programme arrays.
    /// Replacing a row's gap/program geometry while it is focused or under a
    /// drag invalidates cell identities and makes the guide jump. Existing rows
    /// keep their layout; only the matching title's provider-live bit changes.
    /// Channels with no cached data still accept the loaded schedule once.
    func mergeLiveStatus(
        section: String,
        loaded: (channelEPG: [String: ChannelEPG], programs: [String: [EPGProgram]])
    ) {
        var snapshot = sections[section] ?? SectionSnapshot()
        var changed = false

        for (channelId, loadedPrograms) in loaded.programs {
            guard var existing = snapshot.programsByChannel[channelId], !existing.isEmpty else {
                snapshot.programsByChannel[channelId] = loadedPrograms
                changed = true
                continue
            }

            let liveTitle = loadedPrograms.first(where: \.isProviderLive)?.title
            let normalizedLiveTitle = liveTitle?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let now = Date()
            let hasExactAiring = existing.contains { $0.start <= now && now < $0.end }
            var channelChanged = false
            for index in existing.indices {
                let normalizedTitle = existing[index].title
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let shouldBeLive = !hasExactAiring
                    && normalizedLiveTitle != nil
                    && normalizedTitle == normalizedLiveTitle
                guard existing[index].isProviderLive != shouldBeLive else { continue }
                let program = existing[index]
                existing[index] = EPGProgram(
                    title: program.title,
                    description: program.description,
                    start: program.start,
                    end: program.end,
                    isProviderLive: shouldBeLive
                )
                channelChanged = true
            }
            if channelChanged {
                snapshot.programsByChannel[channelId] = existing
                changed = true
            }
        }

        guard changed else { return }
        snapshot.epgByChannel = snapshot.programsByChannel.mapValues {
            EPGLiveLoader.makeChannelEPG(from: $0, now: Date())
        }
        sections[section] = snapshot
        touch(section)
        if section == activeSectionToken {
            programsByChannel = snapshot.programsByChannel
            epgByChannel = snapshot.epgByChannel
        }
    }

    func recomputeNowNext(now: Date = Date()) {
        guard !programsByChannel.isEmpty else { return }
        var next: [String: ChannelEPG] = [:]
        for (channelId, programs) in programsByChannel {
            let epg = EPGLiveLoader.makeChannelEPG(from: programs, now: now)
            if epg.previous != nil || epg.current != nil || epg.next != nil {
                next[channelId] = epg
            }
        }
        epgByChannel = next
        if !activeSectionToken.isEmpty {
            var snapshot = sections[activeSectionToken] ?? SectionSnapshot()
            snapshot.epgByChannel = next
            sections[activeSectionToken] = snapshot
        }
    }

    func channelsNeedingLoad(_ channels: [LiveStream]) -> [LiveStream] {
        // Treat empty arrays as still needing a load — store/warm may have filled
        // in since the last empty result (common during deferred EPG sync).
        // Also reload when a channel has current data but lacks enough future
        // programmes to fill the guide timeline — without this, iOS/macOS
        // guides show only "now" while tvOS displays the full schedule.
        let now = Date()
        return channels.filter {
            let programs = programsByChannel[$0.primaryEPGChannelId] ?? []
            return !EPGLiveLoader.hasAiringProgram(programs, now: now)
                || !EPGBrowseLoader.hasSufficientFutureCoverage(programs, now: now)
        }
    }

    private func touch(_ section: String) {
        sectionOrder.removeAll { $0 == section }
        sectionOrder.append(section)
        while sectionOrder.count > Self.sectionLimit {
            guard let oldest = sectionOrder.first(where: { $0 != activeSectionToken }) else { break }
            sectionOrder.removeAll { $0 == oldest }
            sections.removeValue(forKey: oldest)
        }
    }

    private func persistActiveSection() {
        guard !activeSectionToken.isEmpty else { return }
        sections[activeSectionToken] = SectionSnapshot(
            programsByChannel: programsByChannel,
            epgByChannel: epgByChannel
        )
    }
}
