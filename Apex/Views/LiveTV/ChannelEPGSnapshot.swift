//
//  ChannelEPGSnapshot.swift
//  Apex
//
//  The now/next EPG shown on a channel card, resolved once for a whole list off
//  the main thread. Channel cards used to each register their own `@Query` for
//  EPG listings — a category with hundreds of channels meant hundreds of live
//  SwiftData observers. The list owns a single bounded fetch instead.
//

import Foundation
import SwiftData

/// A point-in-time programme entry for a channel card — plain values so it can
/// cross actor boundaries and outlive the fetch without holding a managed object.
nonisolated struct EPGSlot: Equatable {
    let title: String
    let start: Date
    let end: Date
}

/// The now/next programme pair shown on a single channel card.
nonisolated struct ChannelEPG: Equatable {
    let current: EPGSlot?
    let next: EPGSlot?
}

/// Bounds how much guide data is kept on disk and considered during import.
enum EPGRetention {
    /// Programmes ending more than an hour ago are dropped on sync.
    static let pastGrace: TimeInterval = 3600
    /// Near-term horizon for bulk XMLTV import — the on-screen guide is a 6-hour
    /// window; storing two days ahead keeps memory and SwiftData churn bounded on
    /// large playlists without affecting now/next or the grid.
    static let futureHorizon: TimeInterval = 48 * 3600
    /// Caps rows written per channel during XMLTV import.
    static let maxListingsPerChannel = 16

    nonisolated static func importWindow(now: Date = Date()) -> (start: Date, end: Date) {
        (now.addingTimeInterval(-pastGrace), now.addingTimeInterval(futureHorizon))
    }

    nonisolated static func overlapsImportWindow(start: Date, end: Date, now: Date = Date()) -> Bool {
        let window = importWindow(now: now)
        return end > window.start && start < window.end
    }

    /// Drops programmes that have already ended. Per-channel insert caps bound
    /// memory; `pruneExpiredListings` trims the store after import.
    nonisolated static func shouldImport(start: Date, end: Date, now: Date = Date()) -> Bool {
        _ = start
        return end > now.addingTimeInterval(-pastGrace)
    }
}

