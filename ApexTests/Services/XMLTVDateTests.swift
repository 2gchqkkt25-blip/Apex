//
//  XMLTVDateTests.swift
//  ApexTests
//
//  XMLTV timestamp parsing and timezone detection for Xtream guides.
//

import Foundation
@testable import Apex
import Testing

struct XMLTVDateTests {
    @Test func `parseEPG honors explicit utc offset`() throws {
        // Standard XMLTV: the timestamp states its own offset. `20250626120000 +0200`
        // is an absolute instant (10:00 UTC) regardless of the fallback timezone.
        let expected = Date(timeIntervalSince1970: 1_750_932_000) // 2025-06-26 10:00 UTC

        let parsedWithDeviceHint = try #require(
            XMLTVDate.parseEPG("20250626120000 +0200", timezone: .current)
        )
        let parsedWithUTCHint = try #require(
            XMLTVDate.parseEPG("20250626120000 +0200", timezone: TimeZone(secondsFromGMT: 0))
        )

        // The stated offset wins — the fallback zone is ignored entirely.
        #expect(abs(parsedWithDeviceHint.timeIntervalSince(expected)) < 1)
        #expect(parsedWithDeviceHint == parsedWithUTCHint)
    }

    @Test func `parseEPG treats Z suffix as utc`() throws {
        let expected = Date(timeIntervalSince1970: 1_750_939_200) // 2025-06-26 12:00 UTC
        let parsed = try #require(
            XMLTVDate.parseEPG("20250626120000 Z", timezone: TimeZone(secondsFromGMT: 7_200))
        )
        #expect(abs(parsed.timeIntervalSince(expected)) < 1)
    }

    @Test func `parseEPG uses fallback zone only when no offset is stated`() throws {
        // Offset-less digits are wall clock in the supplied (server) zone.
        let serverTZ = try #require(TimeZone(secondsFromGMT: 7_200))
        let expected = Date(timeIntervalSince1970: 1_750_932_000) // 12:00 in +0200 == 10:00 UTC
        let parsed = try #require(XMLTVDate.parseEPG("20250626120000", timezone: serverTZ))
        #expect(abs(parsed.timeIntervalSince(expected)) < 1)
    }

    @Test func `parse programme times returns the stated absolute interval`() throws {
        // A programme stamped with `+0000` is returned as-is: no shifting toward
        // "now", so the guide agrees with the live stream.
        let times = try #require(
            XMLTVDate.parseProgrammeTimes(
                start: "20250627130000 +0000",
                stop: "20250627140000 +0000"
            )
        )
        #expect(times.start == Date(timeIntervalSince1970: 1_751_029_200)) // 13:00 UTC
        #expect(times.end == Date(timeIntervalSince1970: 1_751_032_800)) // 14:00 UTC
    }

    @Test func `parse programme times rejects non positive interval`() {
        #expect(
            XMLTVDate.parseProgrammeTimes(
                start: "20250627140000 +0000",
                stop: "20250627130000 +0000"
            ) == nil
        )
    }

    @Test func `wall clock digits handles subseconds`() {
        let digits = XMLTVDate.wallClockDigits(from: "20250703120000.0000000 +0000")
        #expect(digits == "20250703120000")
    }

    @Test func `resolve wall clock timezone prefers device when server is gmt`() {
        let gmt = TimeZone(secondsFromGMT: 0)!
        let resolved = XMLTVDate.resolveWallClockTimezone(server: gmt, detected: nil)
        #expect(resolved == .current)
    }

    @Test func `resolve wall clock timezone ignores detected heuristic`() throws {
        let detected = try #require(TimeZone(secondsFromGMT: 7_200))
        let resolved = XMLTVDate.resolveWallClockTimezone(server: TimeZone(secondsFromGMT: 0), detected: detected)
        #expect(resolved == .current)
    }

    @Test func `parseEPG treats bogus gmt plus zero offset as local wall clock`() throws {
        let gmt = try #require(TimeZone(secondsFromGMT: 0))
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = 2026
        components.month = 7
        components.day = 6
        components.hour = 15
        components.minute = 0
        components.second = 0
        let expected = try #require(components.date)
        let parsed = try #require(
            XMLTVDate.parseEPG("20260706150000 +0000", timezone: gmt)
        )
        #expect(abs(parsed.timeIntervalSince(expected)) < 1)
    }

    @Test func `parseEPG xtream flag treats plus zero zero zero zero as local on any device`() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = 2026
        components.month = 7
        components.day = 6
        components.hour = 9
        components.minute = 30
        components.second = 0
        let expected = try #require(components.date)
        let parsed = try #require(
            XMLTVDate.parseEPG(
                "20260706093000 +0000",
                timezone: TimeZone(secondsFromGMT: -14_400),
                treatExplicitZeroOffsetAsLocal: true
            )
        )
        #expect(abs(parsed.timeIntervalSince(expected)) < 1)
    }
}
