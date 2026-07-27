//
//  LiveTVMiniPreview.swift
//  Apex
//
//  Corner floating AVPlayer while browsing Live TV. Wi‑Fi only — on cellular
//  the host falls through to fullscreen playback. Tap / Select the preview to
//  promote it to the full player; pick another channel to retarget the float.
//

import AVFoundation
import SwiftUI

/// Floating live preview shown over the Live TV browse surface.
struct LiveTVMiniPreview: View {
    let media: PlayableMedia
    let onExpand: () -> Void
    let onClose: () -> Void
    /// Explicit width from the host (screen-/pane-scaled on tvOS and macOS).
    /// Falls back to a platform default when omitted.
    var width: CGFloat? = nil

    @StateObject private var coordinator = AVPlayerCoordinator()
    @ObservedObject private var network = NetworkMonitor.shared

    private var previewWidth: CGFloat {
        width ?? Self.defaultWidth
    }

    private static var defaultWidth: CGFloat {
        #if os(tvOS)
            preferredWidth(screenWidth: UIScreen.main.bounds.width)
        #elseif os(macOS)
            300
        #else
            220
        #endif
    }

    /// Size the PiP from the display / content pane so larger screens get a
    /// proportionally larger preview (clamped per platform).
    static func preferredWidth(screenWidth: CGFloat, paneWidth: CGFloat? = nil) -> CGFloat {
        #if os(tvOS)
            let basis = max(screenWidth, paneWidth ?? 0)
            // ~28% of the screen — large enough to watch, small enough to leave
            // most of the guide visible beside it.
            let ideal = basis * 0.28
            return min(max(ideal, 420), 720)
        #elseif os(macOS)
            let basis = max(paneWidth ?? 0, screenWidth * 0.55)
            let ideal = basis * 0.28
            return min(max(ideal, 280), 480)
        #else
            _ = screenWidth
            _ = paneWidth
            return defaultWidth
        #endif
    }

    /// Fixed 16:9 video height — sized up front so the UIKit player host
    /// never mounts at full-overlay size and then shrinks into place.
    private var videoHeight: CGFloat {
        previewWidth * 9 / 16
    }

    /// Title bar under the video — keep total card height fixed for layout.
    private var titleBarHeight: CGFloat {
        #if os(tvOS)
            52
        #else
            40
        #endif
    }

    private var totalHeight: CGFloat {
        videoHeight + titleBarHeight
    }

    var body: some View {
        Group {
            #if os(tvOS)
                tvBody
            #else
                touchBody
            #endif
        }
        // Hard size — tvOS Buttons otherwise expand to the parent proposal.
        .frame(width: previewWidth, height: totalHeight)
        .task(id: media.id) {
            coordinator.startupTimeout = 20
            coordinator.configure(media: media)
        }
        .onChange(of: network.isExpensive) { _, expensive in
            if expensive || network.isConstrained { onClose() }
        }
        .onChange(of: network.isConstrained) { _, constrained in
            if constrained || network.isExpensive { onClose() }
        }
        .onDisappear {
            coordinator.tearDown()
        }
    }

    // MARK: - iOS / macOS

    #if !os(tvOS)
        private var touchBody: some View {
            card
                .onTapGesture(perform: onExpand)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Preview \(media.title)")
                .accessibilityHint("Opens fullscreen player")
        }
    #endif

    // MARK: - tvOS

    #if os(tvOS)
        private var tvBody: some View {
            Button(action: onExpand) {
                card
            }
            .buttonStyle(TVCardButtonStyle(focusScale: 1.04))
            .frame(width: previewWidth, height: totalHeight)
            .accessibilityLabel("Watch \(media.title)")
            .accessibilityHint("Opens fullscreen player")
            .overlay(alignment: .topTrailing) {
                Button(action: onClose) {
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

    /// Explicit VStack — a bare ViewBuilder TupleView overlays children, which
    /// put the channel name across the middle of the video.
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
            MiniPreviewVideoContainer(coordinator: coordinator)
                .frame(width: previewWidth, height: videoHeight)
                .background(Color.black)
                .clipped()
                .allowsHitTesting(false)

            if coordinator.isBuffering, !coordinator.hasStartedPlayback {
                ProgressView()
                    .tint(.white)
                    .frame(width: previewWidth, height: videoHeight)
                    .background(.black.opacity(0.35))
                    .allowsHitTesting(false)
            }

            #if !os(tvOS)
                Button(action: onClose) {
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

// MARK: - Video container

#if os(macOS)
    private struct MiniPreviewVideoContainer: NSViewRepresentable {
        let coordinator: AVPlayerCoordinator

        func makeNSView(context _: Context) -> MiniPreviewHostNSView {
            let view = MiniPreviewHostNSView()
            coordinator.attach(layer: view.playerLayer)
            return view
        }

        func updateNSView(_: MiniPreviewHostNSView, context _: Context) {}
    }

    private final class MiniPreviewHostNSView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            playerLayer.videoGravity = .resizeAspect
            playerLayer.frame = bounds
            layer?.addSublayer(playerLayer)
            layer?.backgroundColor = NSColor.black.cgColor
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }
    }
#else
    private struct MiniPreviewVideoContainer: UIViewRepresentable {
        let coordinator: AVPlayerCoordinator

        func makeUIView(context _: Context) -> MiniPreviewHostUIView {
            let view = MiniPreviewHostUIView()
            view.backgroundColor = .black
            view.clipsToBounds = true
            view.setContentHuggingPriority(.defaultLow, for: .horizontal)
            view.setContentHuggingPriority(.defaultLow, for: .vertical)
            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            coordinator.attach(layer: view.playerLayer)
            return view
        }

        func updateUIView(_: MiniPreviewHostUIView, context _: Context) {}
    }

    private final class MiniPreviewHostUIView: UIView {
        // swiftlint:disable:next static_over_final_class
        override class var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            // swiftlint:disable:next force_cast
            layer as! AVPlayerLayer
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspect
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }
    }
#endif
