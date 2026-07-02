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

    #if os(tvOS)
        @FocusState private var buttonFocused: Bool
        @State private var dismissedSegment: ActiveSegment?
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
        let _ = pollTick
        let position = playbackPosition
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
        .onAppear {
            Logger.player.info("[SkipIntro] Overlay mounted — intro=\(segments.intro != nil, privacy: .public) start=\(segments.intro.map { String(format: "%.1f", $0.start) } ?? "nil", privacy: .public) end=\(segments.intro.map { String(format: "%.1f", $0.end) } ?? "nil", privacy: .public) recap=\(segments.recap != nil, privacy: .public) resume=\(startTime, privacy: .public)")
        }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            pollTick &+= 1
        }
        #if os(tvOS)
            .onChange(of: activeSegment?.segment.end) { _, _ in
                if activeSegment != nil { Task { @MainActor in buttonFocused = true } }
            }
            .onChange(of: segments) { _, _ in
                dismissedSegment = nil
            }
        #endif
    }

    private var playbackPosition: TimeInterval {
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
        let start = max(0, segment.start - timingSlack)
        let end = segment.end + timingSlack
        let duration = end - start
        return duration >= minimumDuration && time >= start && time < end
    }

    private func showsButton(for active: ActiveSegment) -> Bool {
        #if os(tvOS)
            if dismissedSegment == active { return false }
        #endif
        return true
    }

    private func label(for kind: Kind) -> LocalizedStringKey {
        kind == .recap ? "Skip Recap" : "Skip Intro"
    }

    private func skip(_ active: ActiveSegment) {
        onSeek(active.segment.end)
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
