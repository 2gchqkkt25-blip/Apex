//
//  LiveTVMiniPreview.swift
//  Apex
//
//  Corner floating player while browsing Live TV. Wi‑Fi only — on cellular
//  the host falls through to fullscreen playback. Tap / Select the preview to
//  promote it to the full player; pick another channel to retarget the float.
//
//  Uses VLCKit for the float so IPTV/MPEG-TS loads reliably, without sharing
//  KSPlayer's FFmpeg TLS session with the fullscreen player (that overlap was
//  crashing on expand). Fullscreen keeps KSPlayer as the primary engine.
//

import AVFoundation
import OSLog
import SwiftUI
import VLCKitSPM

#if os(macOS)
    import AppKit
#endif

/// Floating live preview shown over the Live TV browse surface.
struct LiveTVMiniPreview: View {
    let media: PlayableMedia
    let onExpand: () -> Void
    let onClose: () -> Void
    /// Explicit width from the host (screen-/pane-scaled on tvOS and macOS).
    /// Falls back to a platform default when omitted.
    var width: CGFloat? = nil

    @StateObject private var vlcCoordinator = VLCPlayerCoordinator()
    /// True once we've begun closing or promoting — ignores late failure
    /// callbacks so they don't re-enter expand.
    @State private var isHandingOff = false
    @ObservedObject private var network = NetworkMonitor.shared

    private var previewWidth: CGFloat {
        width ?? Self.defaultWidth
    }

    private static var defaultWidth: CGFloat {
        #if os(tvOS)
            preferredWidth(screenWidth: UIScreen.main.bounds.width)
        #elseif os(macOS)
            360
        #else
            preferredWidth(screenWidth: UIScreen.main.bounds.width)
        #endif
    }

    /// Size the PiP from the display / content pane. tvOS stays large for
    /// 10-foot viewing; macOS scales up on big monitors; iOS scales for
    /// phone (compact) vs iPad (regular) so the info pane still fits.
    static func preferredWidth(screenWidth: CGFloat, paneWidth: CGFloat? = nil) -> CGFloat {
        #if os(tvOS)
            let basis = max(screenWidth, paneWidth ?? 0)
            let ideal = basis * 0.20
            return min(max(ideal, 320), 480)
        #elseif os(macOS)
            // Prefer the content pane when known; otherwise ~24% of the display.
            let basis = paneWidth ?? screenWidth
            let ideal = basis * 0.24
            return min(max(ideal, 320), 520)
        #else
            let basis = paneWidth ?? screenWidth
            // Phone: leave room for the info pane; iPad: closer to macOS scale.
            if basis < 700 {
                let ideal = basis * 0.38
                return min(max(ideal, 160), 220)
            }
            let ideal = basis * 0.24
            return min(max(ideal, 220), 320)
        #endif
    }

    private var videoHeight: CGFloat {
        previewWidth * 9 / 16
    }

    private var titleBarHeight: CGFloat {
        #if os(tvOS)
            44
        #else
            40
        #endif
    }

    private var totalHeight: CGFloat {
        videoHeight + titleBarHeight
    }

    /// Host layout helpers (e.g. tvOS absolute corner pin) without building the view.
    static func totalHeight(forWidth width: CGFloat) -> CGFloat {
        #if os(tvOS)
            width * 9 / 16 + 44
        #else
            width * 9 / 16 + 40
        #endif
    }

    private var isWaitingForFirstFrame: Bool {
        !vlcCoordinator.hasStartedPlayback
    }

    var body: some View {
        Group {
            #if os(tvOS)
                tvBody
            #else
                touchBody
            #endif
        }
        .frame(width: previewWidth, height: totalHeight)
        .task(id: media.id) {
            await preparePlayback()
        }
        .onChange(of: network.isExpensive) { _, expensive in
            if expensive || network.isConstrained { requestClose() }
        }
        .onChange(of: network.isConstrained) { _, constrained in
            if constrained || network.isExpensive { requestClose() }
        }
        .onDisappear {
            tearDownPlayback()
        }
    }

    // MARK: - Lifecycle

    @MainActor
    private func preparePlayback() async {
        guard !isHandingOff else { return }
        activateAudioSessionIfNeeded()
        vlcCoordinator.startupTimeout = 20
        vlcCoordinator.onPlaybackFailure = {
            Logger.player.error("LiveTV mini preview: VLC failed — expanding")
            onExpand()
        }
        vlcCoordinator.configureLivePreview(media: media)
    }

    @MainActor
    private func requestExpand() {
        guard !isHandingOff else { return }
        isHandingOff = true
        stopPreviewEngine()
        onExpand()
    }

    @MainActor
    private func requestClose() {
        guard !isHandingOff else { return }
        isHandingOff = true
        stopPreviewEngine()
        onClose()
    }

    private func tearDownPlayback() {
        isHandingOff = true
        stopPreviewEngine()
    }

    private func stopPreviewEngine() {
        vlcCoordinator.onPlaybackFailure = nil
        vlcCoordinator.tearDown()
    }

    private func activateAudioSessionIfNeeded() {
        #if os(iOS) || os(tvOS)
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .moviePlayback, options: [])
            try? session.setActive(true, options: [])
        #endif
    }

    // MARK: - iOS / macOS

    #if !os(tvOS)
        private var touchBody: some View {
            card
                .onTapGesture(perform: requestExpand)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Preview \(media.title)")
                .accessibilityHint("Opens fullscreen player")
        }
    #endif

    // MARK: - tvOS

    #if os(tvOS)
        private var tvBody: some View {
            // Plain button + hard frame — `.bordered`/card styles expand into
            // available width on tvOS and visually center the PiP mid-pane.
            Button(action: requestExpand) {
                card
            }
            .buttonStyle(.plain)
            .frame(width: previewWidth, height: totalHeight)
            .focusable(true)
            .accessibilityLabel("Watch \(media.title)")
            .accessibilityHint("Opens fullscreen player")
            .overlay(alignment: .topTrailing) {
                Button(action: requestClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(TVPlayerCircleButtonStyle(diameter: 40, glyphSize: 16))
                .padding(8)
                .accessibilityLabel("Close preview")
            }
        }
    #endif

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 0) {
            videoArea
            titleBar
        }
        .frame(width: previewWidth, height: totalHeight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var videoArea: some View {
        ZStack(alignment: .topTrailing) {
            MiniPreviewVLCContainer(coordinator: vlcCoordinator)
                .frame(width: previewWidth, height: videoHeight)
                .background(Color.black)
                .clipped()
                .allowsHitTesting(false)

            if isWaitingForFirstFrame {
                ProgressView()
                    .tint(.white)
                    .frame(width: previewWidth, height: videoHeight)
                    .background(.black.opacity(0.35))
                    .allowsHitTesting(false)
            }

            #if !os(tvOS)
                Button(action: requestClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.black.opacity(0.55)))
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel("Close preview")
            #endif
        }
        .frame(width: previewWidth, height: videoHeight)
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            if let posterURL = media.posterURL {
                ChannelLogoView(url: posterURL, size: titleLogoSize, cornerRadius: 5, contentPadding: 2)
            }
            Text(media.title)
                #if os(tvOS)
                    .font(.system(size: 20, weight: .semibold))
                #else
                    .font(.caption.weight(.semibold))
                #endif
                    .foregroundStyle(.white)
                    .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                #if os(tvOS)
                    .font(.system(size: 16, weight: .semibold))
                #else
                    .font(.system(size: 11, weight: .semibold))
                #endif
                    .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 12)
        .frame(width: previewWidth, height: titleBarHeight)
        .background(Color.black.opacity(0.85))
    }

    private var titleLogoSize: CGFloat {
        #if os(tvOS)
            32
        #else
            28
        #endif
    }
}

// MARK: - VLC surface

#if os(macOS)
    /// Non-layer-backed host — VLCKit's macOS output uses OpenGL and aborts when
    /// nested in a layer-backed tree (same constraint as `VLCVideoContainer`).
    private struct MiniPreviewVLCContainer: NSViewRepresentable {
        let coordinator: VLCPlayerCoordinator

        func makeNSView(context _: Context) -> NSView {
            let view = NSView(frame: .zero)
            coordinator.attach(hostView: view)
            return view
        }

        func updateNSView(_: NSView, context _: Context) {}
    }
#else
    private struct MiniPreviewVLCContainer: UIViewRepresentable {
        let coordinator: VLCPlayerCoordinator

        func makeUIView(context _: Context) -> UIView {
            let view = UIView()
            view.backgroundColor = .black
            view.clipsToBounds = true
            view.setContentHuggingPriority(.defaultLow, for: .horizontal)
            view.setContentHuggingPriority(.defaultLow, for: .vertical)
            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            coordinator.attach(hostView: view)
            return view
        }

        func updateUIView(_: UIView, context _: Context) {}
    }
#endif
