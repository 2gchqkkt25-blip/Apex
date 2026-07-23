import Combine
import OSLog
import SwiftUI

/// In-player "Skip Intro" / "Skip Recap" affordance, layered above the active
/// engine stack by `FullScreenPlayerView`.
struct PlayerSkipIntroOverlay: View {
    let segments: IntroSegments
    @Bindable var clock: PlaybackClock
    /// Resume offset when the episode opens part-way through — used until the
    /// engine publishes the first playhead sample on `clock`.
    var startTime: TimeInterval = 0
    let onSeek: (TimeInterval) -> Void

    /// Latch the pressed segment on every platform. The clock can take a tick
    /// to reflect an engine seek; without this, the button remains actionable
    /// during that window and can send the playhead backward repeatedly.
    @State private var dismissedSegment: ActiveSegment?

    #if os(tvOS)
        @FocusState private var buttonFocused: Bool
    #endif

    /// Drives re-renders on a cadence so the overlay tracks the playhead even
    /// when Observation doesn't propagate ticks from the host-owned clock.
    @State private var pollTick = 0

    private let minimumDuration: TimeInterval = 3
    /// Widen the match window slightly — IPTV streams often drift vs. streaming
    /// masters that IntroDB was tagged against.
    private let timingSlack: TimeInterval = 20

    private enum Kind: Equatable { case intro, recap }

    private struct ActiveSegment: Equatable {
        let kind: Kind
        let segment: IntroSegments.Segment
    }

    var body: some View {
        let position = playbackPosition(refreshTick: pollTick)
        let activeSegment = activeSegment(at: position)

        Group {
            if let activeSegment, showsButton(for: activeSegment) {
                skipButton(for: activeSegment)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(activeSegment != nil)
        .animation(.easeInOut(duration: 0.25), value: activeSegment?.segment.end)
        .onAppear { logOverlayMounted() }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            pollTick &+= 1
        }
        #if os(tvOS)
        .onChange(of: activeSegment?.segment.end) { _, _ in
            if activeSegment != nil { Task { @MainActor in buttonFocused = true } }
        }
        #endif
        .onChange(of: segments) { _, _ in
            dismissedSegment = nil
        }
    }

    private func playbackPosition(refreshTick _: Int) -> TimeInterval {
        let current = clock.current
        if current.isFinite, current > 0 { return current }
        if startTime.isFinite, startTime > 0 { return startTime }
        return 0
    }

    private func activeSegment(at position: TimeInterval) -> ActiveSegment? {
        guard position > 0 else { return nil }
        if let recap = segments.recap, contains(recap, position) {
            return ActiveSegment(kind: .recap, segment: recap)
        }
        if let intro = segments.intro, contains(intro, position) {
            return ActiveSegment(kind: .intro, segment: intro)
        }
        return nil
    }

    private func contains(_ segment: IntroSegments.Segment, _ time: TimeInterval) -> Bool {
        guard segment.duration >= minimumDuration else { return false }
        let start = max(0, segment.start - timingSlack)
        // Drift allowance belongs before the tagged segment only. Extending the
        // window after `end` left the button visible after its seek target had
        // passed, so pressing it jumped backward and replayed the opening.
        return time >= start && time < segment.end
    }

    private func showsButton(for active: ActiveSegment) -> Bool {
        dismissedSegment != active
    }

    private func logOverlayMounted() {
        let introStart = segments.intro.map { String(format: "%.1f", $0.start) } ?? "nil"
        let introEnd = segments.intro.map { String(format: "%.1f", $0.end) } ?? "nil"
        let message = "[SkipIntro] Overlay mounted — intro=\(segments.intro != nil) "
            + "start=\(introStart) end=\(introEnd) "
            + "recap=\(segments.recap != nil) resume=\(startTime)"
        Logger.player.info("\(message, privacy: .public)")
    }

    private func label(for kind: Kind) -> LocalizedStringKey {
        kind == .recap ? "Skip Recap" : "Skip Intro"
    }

    private func skip(_ active: ActiveSegment) {
        dismissedSegment = active
        let target = max(active.segment.end, playbackPosition(refreshTick: pollTick) + 0.5)
        Logger.player.info("[SkipIntro] Seeking to (target, format: .fixed(precision: 1))s")
        onSeek(target)
    }

    @ViewBuilder
    private func skipButton(for active: ActiveSegment) -> some View {
        #if os(tvOS)
            Button { skip(active) } label: {
                HStack(spacing: 18) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 26, weight: .semibold))
                    Text(label(for: active.kind))
                        .font(.system(size: 24, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 26)
            }
            .buttonStyle(TVGlassButtonStyle())
            .focused($buttonFocused)
            .frame(width: 460)
            .padding(.trailing, 80)
            .padding(.bottom, 60)
            .onExitCommand { dismissedSegment = active }
        #else
            Button { skip(active) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(label(for: active.kind))
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .contentShape(Capsule())
                .glassEffectCompat(.regularInteractive, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
            .padding(.bottom, 100)
        #endif
    }
}
