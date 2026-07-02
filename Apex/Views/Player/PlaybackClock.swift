import Foundation
import Observation

/// The full-screen player's high-frequency state: elapsed time and total
/// duration.
///
/// Kept as an `@Observable` reference type so that ticking the clock several
/// times a second invalidates *only* the views that actually read it — the
/// scrubber and time labels — and nothing else. Were these scalars `@State` on
/// the host (`FullScreenPlayerView`), every tick would re-evaluate the host's
/// body, rebuild the engine view, and re-run KSPlayer's option setup, which was
/// the dominant source of player UI lag on Apple TV's weaker CPU. The host owns
/// the clock and hands bindings to its children, but never reads `current` /
/// `duration` in its own body, so it is not invalidated by playback ticks.
@Observable
final class PlaybackClock {
    var current: TimeInterval = 0
    var duration: TimeInterval = 0

    /// Reset to zero when the host swaps to a different stream.
    func reset() {
        current = 0
        duration = 0
    }
}

/// Seek handle wired by whichever engine view is active. The host-owned Skip
/// Intro overlay lives above the engine stack and forwards seeks through here so
/// it stays visible without duplicating per-engine overlay logic.
@MainActor
@Observable
final class PlayerSeekBridge {
    var seekTo: ((TimeInterval) -> Void)?
    var onAfterSeek: (() -> Void)?

    func seek(_ time: TimeInterval) {
        seekTo?(time)
        onAfterSeek?()
    }

    func reset() {
        seekTo = nil
        onAfterSeek = nil
    }
}
