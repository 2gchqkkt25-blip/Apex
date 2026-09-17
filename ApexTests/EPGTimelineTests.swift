//
//  EPGTimelineTests.swift
//  ApexTests
//

import Foundation
@testable import Apex
import Testing

struct EPGTimelineTests {
    @Test func `empty guide coverage uses half-hour placeholders`() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let timeline = EPGTimeline(
            start: start,
            end: start.addingTimeInterval(3 * 3600),
            pointsPerMinute: 5
        )

        let cells = EPGGridBuilder.cells(for: [EPGProgram](), timeline: timeline)

        #expect(cells.count == 6)
        #expect(cells.allSatisfy { $0.isGap })
        #expect(cells.allSatisfy { $0.end.timeIntervalSince($0.start) <= 30 * 60 })
        #expect(cells.reduce(0) { $0 + $1.width } == timeline.totalWidth)
    }

    @Test func `overlapping programmes stay aligned to the time ruler`() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let timeline = EPGTimeline(
            start: start,
            end: start.addingTimeInterval(3 * 3600),
            pointsPerMinute: 5
        )
        let first = EPGProgram(
            title: "First",
            description: "",
            start: start,
            end: start.addingTimeInterval(90 * 60)
        )
        let overlapping = EPGProgram(
            title: "Second",
            description: "",
            start: start.addingTimeInterval(60 * 60),
            end: start.addingTimeInterval(2 * 3600)
        )

        let cells = EPGGridBuilder.cells(for: [first, overlapping], timeline: timeline)
        let programmeCells = cells.filter { !$0.isGap }

        #expect(programmeCells.count == 2)
        #expect(programmeCells[1].start == first.end)
        #expect(cells.reduce(0) { $0 + $1.width } == timeline.totalWidth)
    }

    @Test func `provider live marker colors a programme with inaccurate timestamps`() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let timeline = EPGTimeline(
            start: now.addingTimeInterval(-2 * 3600),
            end: now.addingTimeInterval(2 * 3600),
            pointsPerMinute: 5
        )
        let providerLive = EPGProgram(
            title: "HBO East",
            description: "",
            start: now.addingTimeInterval(30 * 60),
            end: now.addingTimeInterval(90 * 60),
            isProviderLive: true
        )

        let cells = EPGGridBuilder.cells(for: [providerLive], timeline: timeline)
        let programme = cells.first { !$0.isGap }

        #expect(programme?.isLive(at: now) == true)
        #expect(EPGLiveLoader.hasAiringProgram([providerLive], now: now))
    }

    @Test func `upcoming details alone are not treated as an airing programme`() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let upcoming = EPGProgram(
            title: "Later",
            description: "",
            start: now.addingTimeInterval(30 * 60),
            end: now.addingTimeInterval(90 * 60)
        )

        #expect(!EPGLiveLoader.hasAiringProgram([upcoming], now: now))
        #expect(EPGLiveLoader.hasLiveOrUpcoming([upcoming], now: now))
    }

    @Test func `timestamped current programme wins over a stale provider marker`() {
        let now = Date()
        let timeline = EPGTimeline(
            start: now.addingTimeInterval(-2 * 3600),
            end: now.addingTimeInterval(2 * 3600),
            pointsPerMinute: 5
        )
        let staleFlag = EPGProgram(
            title: "Previous",
            description: "",
            start: now.addingTimeInterval(-90 * 60),
            end: now.addingTimeInterval(-30 * 60),
            isProviderLive: true
        )
        let actualCurrent = EPGProgram(
            title: "Current",
            description: "",
            start: now.addingTimeInterval(-30 * 60),
            end: now.addingTimeInterval(30 * 60)
        )

        let cells = EPGGridBuilder.cells(for: [staleFlag, actualCurrent], timeline: timeline)
        let previousCell = cells.first { $0.title == "Previous" }
        let currentCell = cells.first { $0.title == "Current" }

        #expect(previousCell?.isLive(at: now) == false)
        #expect(currentCell?.isLive(at: now) == true)
    }
}
