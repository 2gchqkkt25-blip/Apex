//
//  DeviceMemoryTier.swift
//  Apex
//
//  Apple TV HD (2 GB RAM) jetsam kills apps far sooner than Mac or Apple TV 4K.
//  Use this to tighten caches and defer background work on constrained devices.
//

import Foundation

#if os(tvOS)
import Darwin
#endif

enum DeviceMemoryTier: Sendable {
    case standard
    /// Apple TV HD and other low-RAM tvOS hosts (~1.5 GB app limit).
    case constrained

    static let current: DeviceMemoryTier = {
        #if os(tvOS)
        if isAppleTVHD {
            return .constrained
        }
        // Some tvOS hosts under-report or round `physicalMemory`; treat ≤3.5 GB as constrained.
        if ProcessInfo.processInfo.physicalMemory <= 3_500_000_000 {
            return .constrained
        }
        #endif
        return .standard
    }()

    var isConstrained: Bool {
        self == .constrained
    }

    /// Ceiling on how many rows a paginated browse grid may accumulate, or `nil`
    /// for no limit. These grids append each fetched page into view state and
    /// never trim, so a deep scroll through a 20K-title category keeps every
    /// hydrated model — and its decoded poster — alive at once. Apple TV HD
    /// can't afford that against a ~1.5 GB budget. Trimming already-loaded
    /// pages instead would yank content out from under the user's scroll
    /// position, so stop paging rather than evict.
    var maxPaginatedBrowseItems: Int? {
        isConstrained ? 300 : nil
    }

    /// False on Apple TV HD, where cross-fading a *full-screen* subtree is not
    /// worth its cost: UIKit snapshots both the outgoing and incoming
    /// hierarchies to animate them (the `_UIReplicantView` console warnings),
    /// and each snapshot is a full-screen bitmap. Against a ~1.5 GB budget
    /// those transient allocations are a real jetsam contributor, so swap
    /// instantly there and keep the polish on roomier devices.
    var allowsFullScreenCrossFade: Bool {
        !isConstrained
    }

    #if os(tvOS)
    /// Apple TV HD (1080p, 2 GB). `physicalMemory` alone is unreliable on older tvOS builds.
    private static var isAppleTVHD: Bool {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return false }
        var machine = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 else { return false }
        let model = String(cString: machine)
        return model == "AppleTV6,2" || model == "AppleTV5,3"
    }
    #endif
}
