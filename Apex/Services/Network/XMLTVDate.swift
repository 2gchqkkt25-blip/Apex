//
//  XMLTVDate.swift
//  Apex
//
//  Parses XMLTV programme timestamps (`YYYYMMDDHHMMSS ±HHMM`).
//

import Foundation

enum XMLTVDate {
    nonisolated(unsafe) private static let sqlWallClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Resolves a programme's `(start, end)` from its XMLTV attributes.
    ///
    /// Standard XMLTV timestamps are self-describing (`YYYYMMDDHHMMSS +ZZZZ`), so
    /// `parseEPG` honours the stated offset and returns an absolute instant — no
    /// timezone guessing, no "slide it near now" heuristic (both fabricated data
    /// and made the guide disagree with the live stream). Only offset-*less*
    /// timestamps fall back to the supplied `timezone` (server zone, else device).
    nonisolated static func parseProgrammeTimes(
        start startRaw: String?,
        stop stopRaw: String?,
        now: Date = Date(),
        timezone: TimeZone? = nil,
        /// Xtream `xmltv.php` dumps often stamp *local* wall-clock digits with a
        /// bogus `+0000` suffix. When true, `+0000`/`Z` are read as device-local
        /// wall clock instead of literal UTC.
        treatExplicitZeroOffsetAsLocal: Bool = false,
        /// When set, `+0000`/`Z` wall-clock digits are read in this zone (between
        /// the Xtream-local and literal-UTC interpretations).
        interpretZeroOffsetIn: TimeZone? = nil
    ) -> (start: Date, end: Date)? {
        guard let startText = startRaw?.trimmingCharacters(in: .whitespacesAndNewlines),
              let stopText = stopRaw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !startText.isEmpty, !stopText.isEmpty,
              let start = parseEPG(
                startText,
                timezone: timezone,
                treatExplicitZeroOffsetAsLocal: treatExplicitZeroOffsetAsLocal,
                interpretZeroOffsetIn: interpretZeroOffsetIn
              ),
              let end = parseEPG(
                stopText,
                timezone: timezone,
                treatExplicitZeroOffsetAsLocal: treatExplicitZeroOffsetAsLocal,
                interpretZeroOffsetIn: interpretZeroOffsetIn
              ),
              end > start
        else { return nil }
        return (start, end)
    }

    /// Parses an XMLTV timestamp. If it states an explicit UTC offset it is an
    /// absolute instant and is honoured as-is; otherwise the wall-clock digits
    /// are interpreted in `timezone` (server zone, else device).
    nonisolated static func parseEPG(
        _ dateString: String?,
        timezone: TimeZone? = nil,
        treatExplicitZeroOffsetAsLocal: Bool = false,
        interpretZeroOffsetIn zone: TimeZone? = nil
    ) -> Date? {
        guard let dateString, !dateString.isEmpty else { return nil }
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let zeroOffset = explicitOffsetSeconds(afterDigitsIn: trimmed) == 0
        let digits = wallClockDigits(from: trimmed)

        // Xtream xmltv.php: local wall-clock with a lying `+0000` / `Z` suffix.
        if treatExplicitZeroOffsetAsLocal,
           zeroOffset,
           let digits,
           let local = localParse(digits, timezone: .current)
        {
            return local
        }

        // `+0000` wall clock in the provider's own zone (common when the panel
        // reports `America/New_York` but still suffixes `+0000`).
        if zeroOffset,
           let zone,
           let digits,
           let local = localParse(digits, timezone: zone)
        {
            return local
        }

        // Server reports GMT while stamping local wall-clock with `+0000`.
        if let digits,
           zeroOffset,
           isZeroOffset(timezone),
           let local = localParse(digits, timezone: .current)
        {
            return local
        }

        // Honour an explicit offset ("… +0100", "…Z", "… -0500") — absolute.
        if let absolute = parseWithExplicitOffset(trimmed) { return absolute }

        // 2. Offset-less: interpret the wall clock in the supplied zone.
        let zone = timezone ?? .current
        if let digits = wallClockDigits(from: trimmed),
           let local = localParse(digits, timezone: zone)
        {
            return local
        }
        return parseAlternateFormats(trimmed, timezone: zone)
    }

    /// Parses `YYYYMMDDHHMMSS` plus an explicit offset (`+HHMM`, `-HH:MM`, `Z`)
    /// appearing after the 14 date digits (tolerates subseconds like
    /// `…​.000 +0000`). Returns `nil` when no offset token is present.
    nonisolated private static func parseWithExplicitOffset(_ string: String) -> Date? {
        guard let digits = wallClockDigits(from: string),
              let offset = explicitOffsetSeconds(afterDigitsIn: string)
        else { return nil }
        let b = Array(digits.utf8)
        func field(_ start: Int, _ count: Int) -> Int {
            var value = 0
            for i in start ..< start + count { value = value * 10 + Int(b[i] - 0x30) }
            return value
        }
        let year = field(0, 4), month = field(4, 2), day = field(6, 2)
        let hour = field(8, 2), minute = field(10, 2), second = field(12, 2)
        guard month >= 1, month <= 12, day >= 1, day <= 31,
              hour < 24, minute < 60, second < 60 else { return nil }
        let days = daysFromCivil(year: year, month: month, day: day)
        let epoch = days * 86_400 + hour * 3_600 + minute * 60 + second - offset
        return Date(timeIntervalSince1970: TimeInterval(epoch))
    }

    /// UTC offset (seconds) that follows the 14-digit wall-clock run.
    /// `Z`/`z` → 0; `+HHMM` / `-HH:MM` / `+HH` → signed seconds; `nil` if absent.
    nonisolated private static func explicitOffsetSeconds(afterDigitsIn string: String) -> Int? {
        var digitCount = 0
        var tail = Substring()
        var index = string.startIndex
        while index < string.endIndex {
            if string[index].isNumber {
                digitCount += 1
                if digitCount == 14 {
                    tail = string[string.index(after: index)...]
                    break
                }
            } else if digitCount > 0 {
                return nil // digit run shorter than 14 — not an XMLTV timestamp
            }
            index = string.index(after: index)
        }
        guard digitCount == 14 else { return nil }

        let rest = tail.trimmingCharacters(in: .whitespaces)
        guard let signIndex = rest.firstIndex(where: { $0 == "+" || $0 == "-" }) else {
            if let first = rest.first, first == "Z" || first == "z" { return 0 }
            return nil
        }
        let sign = rest[signIndex] == "+" ? 1 : -1
        let offsetDigits = Array(rest[rest.index(after: signIndex)...].filter(\.isNumber))
        guard offsetDigits.count >= 2 else { return nil }
        let hours = Int(String(offsetDigits[0 ..< 2])) ?? 0
        let minutes = offsetDigits.count >= 4 ? (Int(String(offsetDigits[2 ..< 4])) ?? 0) : 0
        guard hours <= 14, minutes < 60 else { return nil }
        return sign * (hours * 3_600 + minutes * 60)
    }

    /// Lexicographic sort key for XMLTV wall-clock timestamps (`YYYYMMDDHHMMSS`).
    nonisolated static func wallClockSortKey(_ raw: String?) -> String {
        wallClockDigits(from: raw ?? "") ?? ""
    }

    /// Xtream panels often report `GMT` / `UTC` while stamping local wall-clock digits.
    nonisolated static func isZeroOffset(_ timezone: TimeZone?) -> Bool {
        timezone?.secondsFromGMT() == 0
    }

    /// Extracts the first 14-digit `YYYYMMDDHHMMSS` run from an XMLTV timestamp.
    /// Handles subseconds (`20250703120000.000 +0000`) and compact values.
    nonisolated static func wallClockDigits(from string: String) -> String? {
        var digits = ""
        for scalar in string.unicodeScalars {
            if scalar.value >= 0x30, scalar.value <= 0x39 {
                digits.unicodeScalars.append(scalar)
                if digits.count == 14 { return digits }
            } else if !digits.isEmpty {
                break
            }
        }
        return digits.count == 14 ? digits : nil
    }

    /// Some panels emit SQL-style timestamps or unix seconds in XMLTV attributes.
    nonisolated private static func parseAlternateFormats(_ string: String, timezone: TimeZone) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let interval = TimeInterval(trimmed), interval > 1_000_000_000 {
            return Date(timeIntervalSince1970: interval)
        }
        if trimmed.contains("-") {
            let formatter = sqlWallClockFormatter
            formatter.timeZone = timezone
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    /// Resolves which zone should interpret offset-less XMLTV wall-clock digits.
    ///
    /// Non-zero server offsets are trusted. When the server reports GMT/UTC
    /// (common on Xtream), device local time is used — many panels stamp local
    /// wall clock with a bogus `+0000` suffix (handled in `parseEPG` too).
    nonisolated static func resolveWallClockTimezone(
        server: TimeZone?,
        detected: TimeZone?
    ) -> TimeZone {
        if let server, !isZeroOffset(server) { return server }
        return .current
    }

    /// `YYYYMMDDHHMMSS` with no timezone — common on Xtream XMLTV dumps.
    nonisolated private static func localParse(_ string: String, timezone: TimeZone = .current) -> Date? {
        let bytes = Array(string.utf8)
        guard bytes.count == 14 else { return nil }

        func digits(_ start: Int, _ count: Int) -> Int? {
            var value = 0
            for offset in start ..< (start + count) {
                let byte = bytes[offset]
                guard byte >= 0x30, byte <= 0x39 else { return nil }
                value = value * 10 + Int(byte - 0x30)
            }
            return value
        }

        guard let year = digits(0, 4), let month = digits(4, 2), let day = digits(6, 2),
              let hour = digits(8, 2), let minute = digits(10, 2), let second = digits(12, 2),
              month >= 1, month <= 12, day >= 1, day <= 31,
              hour < 24, minute < 60, second < 60
        else { return nil }

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = timezone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date
    }

    nonisolated private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let adjustedYear = month <= 2 ? year - 1 : year
        let era = (adjustedYear >= 0 ? adjustedYear : adjustedYear - 399) / 400
        let yearOfEra = adjustedYear - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    // MARK: - Timezone helpers

    /// Parses a timezone from a raw string that may be an IANA identifier
    /// (`"Europe/London"`) or a GMT offset (`"+0200"`, `"+02:00"`, `"UTC+2"`).
    nonisolated static func timezone(from raw: String?) -> TimeZone? {
        guard let raw, !raw.isEmpty else { return nil }
        if let tz = TimeZone(identifier: raw) { return tz }
        var cleaned = raw
            .replacingOccurrences(of: "UTC", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "GMT", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        let sign: Int
        if cleaned.hasPrefix("+") { sign = 1 }
        else if cleaned.hasPrefix("-") { sign = -1 }
        else { return nil }
        cleaned = String(cleaned.dropFirst())
        let parts = cleaned.components(separatedBy: ":")
        if parts.count == 2,
           let h = Int(parts[0]), let m = Int(parts[1]),
           (0 ... 23).contains(h), (0 ... 59).contains(m)
        {
            return TimeZone(secondsFromGMT: sign * (h * 3600 + m * 60))
        }
        if parts.count == 1 {
            if cleaned.count == 4,
               let h = Int(cleaned.prefix(2)), let m = Int(cleaned.suffix(2))
            {
                return TimeZone(secondsFromGMT: sign * (h * 3600 + m * 60))
            }
            if let h = Int(cleaned), (0 ... 23).contains(h) {
                return TimeZone(secondsFromGMT: sign * h * 3600)
            }
        }
        return nil
    }
}
