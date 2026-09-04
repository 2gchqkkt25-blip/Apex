//
//  PlaybackSession.swift
//  Apex
//
//  Only one playback engine may produce audio at a time. SwiftUI can keep a
//  dismissing fullScreenCover alive long enough for a new movie/episode player
//  to start, so the outgoing engine is stopped the moment a new session claims
//  the slot — not later in `onDisappear`.
//

import AVFoundation
import Foundation

@MainActor
enum PlaybackSession {
    private static var generation = 0
    private static var stopHandler: (() -> Void)?

    /// True while a player (or live mini-preview) has claimed the slot.
    static var isActive: Bool { stopHandler != nil }

    /// Makes `stop` the exclusive teardown for this process. Immediately runs
    /// the previous session's stop so its audio cannot overlap the new one.
    /// Returns a token for `resign(_:)`.
    @discardableResult
    static func becomeActive(_ stop: @escaping () -> Void) -> Int {
        generation += 1
        let token = generation
        let previous = stopHandler
        stopHandler = stop
        previous?()
        return token
    }

    /// Drops this session if it is still the active one. A newer claim is left
    /// untouched so a dismissing player cannot clear the replacement.
    static func resign(_ token: Int) {
        guard token == generation else { return }
        stopHandler = nil
    }

    /// Stops the current engine immediately (close button, new player `.task`).
    static func stopActive() {
        let stop = stopHandler
        stopHandler = nil
        stop?()
    }

    /// Deactivates the shared audio session only if nothing else has claimed
    /// playback. Delayed so a incoming player can register before the outgoing
    /// cover's `onDisappear` runs.
    static func scheduleAudioSessionRelease() {
        let token = generation
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard token == generation, stopHandler == nil else { return }
            #if os(iOS) || os(tvOS)
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
        }
    }

    #if DEBUG
        static func resetForTests() {
            generation = 0
            stopHandler = nil
        }
    #endif
}
