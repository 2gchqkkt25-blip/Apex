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
}
