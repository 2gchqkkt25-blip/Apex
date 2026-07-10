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
  private(set) var activeSectionToken: String = ""

  func activate(section: String) {
    guard activeSectionToken != section else { return }
    persistActiveSection()
    activeSectionToken = section
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
    for (channelId, programs) in loaded.programs {
      snapshot.programsByChannel[channelId] = programs
    }
    for (channelId, epg) in loaded.channelEPG {
      snapshot.epgByChannel[channelId] = epg
    }
    sections[section] = snapshot
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
      if epg.current != nil || epg.next != nil {
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
    channels.filter { programsByChannel[$0.primaryEPGChannelId] == nil }
  }

  private func persistActiveSection() {
    guard !activeSectionToken.isEmpty else { return }
    sections[activeSectionToken] = SectionSnapshot(
      programsByChannel: programsByChannel,
      epgByChannel: epgByChannel
    )
  }
}
