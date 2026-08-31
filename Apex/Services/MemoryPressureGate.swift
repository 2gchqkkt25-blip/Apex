//
//  MemoryPressureGate.swift
//  Apex
//
//  Briefly suppresses work that allocates heavily (image decode/prefetch,
//  EPG live gap-fill, hero warm-up) after UIKit posts a memory warning.
//  Apple TV jetsam often follows a burst of warnings — pausing optional work
//  for a minute gives the system room to recover.
//

import Foundation

enum MemoryPressureGate {
    private static let lock = NSLock()
    private static var activeUntil: Date?

    /// True while optional heavy work should stay paused.
    static var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let until = activeUntil else { return false }
        if until > Date() { return true }
        activeUntil = nil
        return false
    }

    /// Called from `ImageMemoryCache` on `UIApplication.didReceiveMemoryWarning`.
    static func noteMemoryWarning(cooldown: TimeInterval = 60) {
        lock.lock()
        activeUntil = Date().addingTimeInterval(cooldown)
        lock.unlock()

        Task { @MainActor in
            ContentIndexingService.shared.cancelForMemoryPressure()
        }
        Task {
            await ImagePipeline.shared.cancelAllInFlight()
        }
    }
}

/// Drops optional allocations when full-screen playback starts so decoder
/// buffers have headroom on Apple TV HD (~1.5 GB jetsam budget).
enum PlaybackMemoryGate {
    static func prepareForPlayback() {
        ImageMemoryCache.shared.purge(reason: "playback started")
        URLCache.shared.removeAllCachedResponses()
        Task {
            await ImagePipeline.shared.cancelAllInFlight()
        }
    }

    /// Aggressive cleanup when UIKit warns during an active decode session.
    static func noteMemoryWarningDuringPlayback() {
        guard suppressesImageLoads else { return }
        ImageMemoryCache.shared.purge(reason: "playback memory warning")
        Task {
            await ImagePipeline.shared.cancelAllInFlight()
        }
        Task { @MainActor in
            ContentIndexingService.shared.cancelForMemoryPressure()
        }
    }

    static var suppressesImageLoads: Bool {
        ContentIndexingService.shared.isPlaybackActive
    }
}
