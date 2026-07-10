//
//  XtreamEPGTimestampTests.swift
//  ApexTests
//
//  Xtream short-EPG timestamp formats must not be misread as unix seconds.
//

import Foundation
@testable import Apex
import Testing

struct XtreamEPGTimestampTests {
    @Test func `unix seconds string`() {
        let date = XtreamEPGText.parseTimestamp("1751569200")
        #expect(date == Date(timeIntervalSince1970: 1_751_569_200))
    }

    @Test func `unix seconds int-like field via short epg`() throws {
        let json = Data("""
        {"start_timestamp": 1751569200, "stop_timestamp": 1751572800, "title": "News"}
        """.utf8)
        let epg = try JSONDecoder().decode(XtreamShortEPG.self, from: json)
        #expect(epg.startDate(timezoneIdentifier: nil) == Date(timeIntervalSince1970: 1_751_569_200))
        #expect(epg.endDate(timezoneIdentifier: nil) == Date(timeIntervalSince1970: 1_751_572_800))
    }

    @Test func `xmltv compact digits are not treated as unix`() {
        // Regression: TimeInterval("20260703150000") used to succeed and land
        // programmes in year ~642000, so the guide showed nothing.
        let zone = TimeZone(secondsFromGMT: -4 * 3600)!
        let date = XtreamEPGText.parseTimestamp("20260703150000", timezoneIdentifier: zone.identifier)
        let expected = XMLTVDate.parseEPG("20260703150000", timezone: zone)
        #expect(date == expected)
        #expect(date != Date(timeIntervalSince1970: 20_260_703_150_000))
    }

    @Test func `sql wall clock`() {
        let zone = TimeZone(identifier: "America/New_York")!
        let date = XtreamEPGText.parseTimestamp("2026-07-03 15:00:00", timezoneIdentifier: zone.identifier)
        #expect(date != nil)
        let components = Calendar(identifier: .gregorian).dateComponents(in: zone, from: date!)
        #expect(components.year == 2026)
        #expect(components.month == 7)
        #expect(components.day == 3)
        #expect(components.hour == 15)
    }

    @Test func `base64 title decodes`() throws {
        let json = Data("""
        {"start_timestamp": "1751569200", "stop_timestamp": "1751572800", "title": "TmV3cw=="}
        """.utf8)
        let epg = try JSONDecoder().decode(XtreamShortEPG.self, from: json)
        #expect(epg.decodedTitle == "News")
    }

    @Test func `parsed programme falls inside guide window`() {
        let now = Date(timeIntervalSince1970: 1_751_569_200) // 2025-07-03-ish
        let startRaw = String(Int(now.addingTimeInterval(-600).timeIntervalSince1970))
        let endRaw = String(Int(now.addingTimeInterval(1800).timeIntervalSince1970))
        let start = XtreamEPGText.parseTimestamp(startRaw)!
        let end = XtreamEPGText.parseTimestamp(endRaw)!
        #expect(EPGRetention.overlapsImportWindow(start: start, end: end, now: now))
    }

    @Test func `prefers live wall clock when unix timestamp is stale`() {
        let zone = TimeZone(identifier: "America/New_York")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 14, minute: 30))!
        let staleStart = Int(now.addingTimeInterval(-4 * 86_400).timeIntervalSince1970)
        let staleEnd = staleStart + 3600
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        let liveStart = now.addingTimeInterval(-15 * 60)
        let liveEnd = now.addingTimeInterval(45 * 60)

        let epg = XtreamShortEPG(
            start: formatter.string(from: liveStart),
            end: formatter.string(from: liveEnd),
            startTimestamp: String(staleStart),
            stopTimestamp: String(staleEnd),
            title: "Live News"
        )

        let times = epg.programmeTimes(timezoneIdentifier: zone.identifier, now: now)
        #expect(times != nil)
        #expect(times!.start == liveStart)
        #expect(times!.end == liveEnd)
        #expect(times!.start <= now && now < times!.end)
    }

    @Test func `now playing row is treated as current`() {
        let now = Date(timeIntervalSince1970: 1_751_569_200)
        let staleStart = Int(now.addingTimeInterval(-3 * 86_400).timeIntervalSince1970)
        let epg = XtreamShortEPG(
            startTimestamp: String(staleStart),
            stopTimestamp: String(staleStart + 3600),
            title: "On Air",
            nowPlaying: true
        )
        let times = epg.programmeTimes(timezoneIdentifier: nil, now: now)
        #expect(times != nil)
        #expect(times!.start <= now)
        #expect(times!.end > now)
    }

    @Test func `parse preserves real provider timestamps without shifting`() {
        // When provider data is recent (within 1h of now), parse returns
        // timestamps exactly as sent. When data is stale (all ended > 1h ago),
        // it cycles forward by whole days to cover now — this is how other IPTV
        // apps display stale EPG feeds.
        let now = Date(timeIntervalSince1970: 1_782_799_200) // Current time
        let listings = (0 ..< 3).map { index -> XtreamShortEPG in
            // Recent data — within the current hour
            let start = Int(now.timeIntervalSince1970) - 600 + index * 1800
            return XtreamShortEPG(
                startTimestamp: String(start),
                stopTimestamp: String(start + 1800),
                title: index == 0 ? "Highlights" : "Slot \(index)"
            )
        }

        let programs = EPGAPISync.parse(listings, timezoneIdentifier: nil, now: now)
        #expect(programs.count == 3)
        // Recent data — times are exactly what the provider sent (no shift).
        #expect(programs[0].title == "Highlights")
        #expect(programs[0].start == Date(timeIntervalSince1970: TimeInterval(Int(now.timeIntervalSince1970) - 600)))
    }
}
