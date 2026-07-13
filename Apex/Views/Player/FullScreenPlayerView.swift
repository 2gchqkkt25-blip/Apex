import AVFoundation
import OSLog
import SwiftData
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Top-level full-screen video host. Picks the engine implementation based on
/// the user setting, owns progress state, and persists watch progress back
/// into SwiftData for VOD content.
struct FullScreenPlayerView: View {
    let media: PlayableMedia

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
        @Environment(\.dismissWindow) private var dismissWindow
    #endif

    /// The user's ordered engine fallback list, read once when the player opens.
    /// Settings changes don't reshuffle a session already in flight; reopening
    /// the player picks up the new order. See `PlayerEnginePriority`.
    private let enginePriority: [PlayerEngineKind]

    /// Index into `enginePriority` of the engine currently driving playback.
    /// Advanced when an engine fails to start a stream, falling the player back
    /// to the next engine in the list. Reset to the primary engine whenever the
    /// active stream changes.
    @State private var engineAttempt = 0

    /// The only high-frequency playback state. An `@Observable` the host owns
    /// but never reads in its own body, so playback ticks invalidate just the
    /// scrubber/time labels rather than re-rendering the whole player tree. See
    /// `PlaybackClock`.
    @State private var clock = PlaybackClock()

    /// Writes watch progress on a private background `ModelContext`. Saving on
    /// the main context mid-playback hitches KSPlayer's render loop, so the
    /// sampler below only reads the clock and hands `Sendable` values to this
    /// actor. Created in `.task` once the environment's container is available.
    @State private var progressWriter: WatchProgressWriter?

    /// The stream currently playing. Starts as `media` but can be swapped when
    /// the viewer picks another episode from the in-player episode rail (tvOS).
    @State private var activeMedia: PlayableMedia

    /// The Stalker-resolved stand-in for `activeMedia`. Stalker streams arrive as
    /// a `lumestalker://` placeholder whose real URL is fetched via `create_link`
    /// at playback time; this holds the resolved copy once it lands. `nil` while
    /// resolution is in flight (the loading indicator shows). Engines that play a
    /// directly usable URL (Xtream / m3u) bypass this entirely — see `displayMedia`.
    @State private var resolvedMedia: PlayableMedia?

    /// Set when Stalker `create_link` resolution fails, so the host shows the
    /// failure overlay instead of an endless spinner.
    @State private var resolveError: String?

    /// Stremio stream picker state. When multiple streams are available, the user
    /// can choose quality/source instead of auto-selecting.
    @State private var stremioStreamOptions: [StremioStreamOption] = []
    @State private var showStreamPicker = false

    /// The episode queued to play after `activeMedia`, resolved whenever the
    /// active stream changes. Drives both the in-player Next Episode button and
    /// auto-advance (see `PlayerNextUpOverlay`); `nil` for movies, live channels
    /// and series finales. Read only when the player tree is (re)built, never on
    /// the per-tick clock path.
    @State private var nextUpMedia: PlayableMedia?

    /// Intro / recap timestamps for the active episode (from IntroDB), driving
    /// the in-player Skip Intro button. `nil` for movies, live channels, and
    /// episodes IntroDB doesn't know — resolved whenever the active stream
    /// changes. Read only when the player tree is (re)built, never on the
    /// per-tick clock path. See `PlayerSkipIntroOverlay`.
    @State private var skipSegments: IntroSegments?
    /// Wired by the active engine so the host-level skip overlay can seek.
    @State private var seekBridge = PlayerSeekBridge()

    /// External subtitle file URL (from OpenSubtitles.com). Set when the stream
    /// doesn't have embedded subtitle tracks and OpenSubtitles is configured.
    @State private var externalSubtitleURL: URL?

    init(media: PlayableMedia) {
        self.media = media
        _activeMedia = State(initialValue: media)
        let defaults = UserDefaults.standard
        enginePriority = PlayerEnginePriority.resolve(
            priorityRaw: defaults.string(forKey: PlayerSettings.enginePriorityKey) ?? "",
            legacyEngineRaw: defaults.string(forKey: PlayerSettings.engineKey)
                ?? PlayerEngineKind.defaultValue.rawValue
        )
    }

    /// The engine driving the current playback attempt.
    private var engine: PlayerEngineKind {
        guard enginePriority.indices.contains(engineAttempt) else { return .defaultValue }
        return enginePriority[engineAttempt]
    }

    /// Whether another engine remains to fall back to after the current one.
    private var hasFallbackEngine: Bool {
        engineAttempt + 1 < enginePriority.count
    }

    /// Called by an engine when it can't start the stream. Advances to the next
    /// engine in the priority list if one is available; the engine view rebuilds
    /// against the new engine. When the list is exhausted this is never called
    /// (the last engine shows its own error overlay instead), so there's nothing
    /// to do here in that case.
    private func fallBackToNextEngine() {
        guard hasFallbackEngine else { return }
        let failed = engine
        engineAttempt += 1
        Logger.player.log("engine \(failed.rawValue, privacy: .public) could not start the stream; falling back to \(engine.rawValue, privacy: .public)")
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            playerView
                .ignoresSafeArea()

            if displayMedia != nil, let skipSegments {
                PlayerSkipIntroOverlay(
                    segments: skipSegments,
                    clock: clock,
                    startTime: activeMedia.startTime,
                    onSeek: { seekBridge.seek($0) }
                )
                .zIndex(100)
            }

            // External subtitles (OpenSubtitles.com) — shown when the stream
            // doesn't have embedded subtitle tracks.
            if displayMedia != nil, let externalSubtitleURL {
                ExternalSubtitleOverlay(
                    subtitleURL: externalSubtitleURL,
                    clock: clock
                )
                .zIndex(99)
            }

            // VLCKit and KSPlayer ship their own close button inside the
            // auto-hiding controls overlay — showing a second one here means
            // the user sees duplicate X buttons whenever the controls are
            // visible. Only render our custom close for engines that don't
            // draw their own controls.
            if !engine.rendersOwnControls {
                closeButton
                    .padding(.top, 4)
                    .padding(.leading, 4)
            }
        }
        #if os(iOS)
        .statusBarHidden(true)
        #endif
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showStreamPicker) {
            StremioStreamPickerView(
                streams: stremioStreamOptions,
                onSelect: selectStremioStream,
                onCancel: {
                    showStreamPicker = false
                    // If user cancels without picking, auto-select the best
                    if let best = stremioStreamOptions.first {
                        resolvedMedia = mediaWith(url: best.url)
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .task {
            // Seed the recall pair with the channel we opened on, so the very
            // first in-player recall has somewhere to jump back to.
            LiveChannelHistory.record(activeMedia)
            // Pause background indexing — its periodic saves merge into the
            // main context and hitch KSPlayer's render loop.
            ContentIndexingService.shared.isPlaybackActive = true
            configureAudioSessionForPlayback()
            #if os(macOS)
                enterMacFullScreen()
            #endif
        }
        .task(id: activeMedia.id) {
            // Resolve a deferred Stalker placeholder into a real (short-lived)
            // stream URL before the engine loads it. No-op for Xtream / m3u.
            await resolveActiveMedia()
        }
        .task(id: activeMedia.id) {
            // Resolve the next episode for the active stream. Runs on appear and
            // whenever the stream swaps (manual pick or auto-advance), so the
            // queued episode always trails the one on screen.
            nextUpMedia = activeMedia.isLive
                ? nil
                : NextEpisodeResolver.nextMedia(after: activeMedia.contentRef, in: modelContext)
        }
        .task(id: activeMedia.id) {
            // Resolve the IntroDB skip windows for the active episode. Runs on
            // appear and whenever the stream swaps. Gated on the user setting so
            // a disabled feature makes no network call. The lookup may fetch the
            // series' IMDb ID from TMDB on first encounter, so it is now async.
            skipSegments = nil
            guard PlayerSettings.Playback.canUseSkipIntro else {
                Logger.player.info("[SkipIntro] Skipped — setting disabled in Settings → Playback")
                return
            }
            guard !activeMedia.isLive else {
                Logger.player.info("[SkipIntro] Skipped — live stream")
                return
            }
            guard let lookup = await IntroSkipResolver.lookup(for: activeMedia.contentRef, in: modelContext) else {
                Logger.player.info("[SkipIntro] Skipped — no lookup key (missing IMDb ID / not an episode)")
                return
            }
            Logger.player.info("[SkipIntro] Lookup resolved: imdb=\(lookup.imdbId, privacy: .public) s\(lookup.season)e\(lookup.episode) — fetching from IntroDB")
            do {
                if let segments = try await IntroDBClient.shared.skippableSegments(
                    imdbId: lookup.imdbId, season: lookup.season, episode: lookup.episode
                ) {
                    Logger.player.info("[SkipIntro] Segments received: intro=\(segments.intro != nil, privacy: .public) recap=\(segments.recap != nil, privacy: .public)")
                    skipSegments = segments
                } else {
                    Logger.player.info("[SkipIntro] No intro/recap in IntroDB for s\(lookup.season)e\(lookup.episode) — this episode may have no skippable opener (BB S1E1 is a known example)")
                }
            } catch {
                Logger.player.warning("[SkipIntro] IntroDB request failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        .task(id: activeMedia.id) {
            // Fetch external subtitles from OpenSubtitles.com when configured.
            // Only for VOD content (not live) and only when no embedded tracks
            // are detected after a brief delay.
            externalSubtitleURL = nil
            guard !activeMedia.isLive else { return }
            guard OpenSubtitlesClient.shared.isConfigured else { return }
            guard UserDefaults.standard.bool(forKey: OpenSubtitlesSettings.enabledKey) else { return }

            // Wait briefly for the stream to load and expose its tracks.
            // If embedded subs exist, the user can pick those instead.
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }

            // Resolve IMDB ID from the content reference
            let imdbId: String?
            let season: Int?
            let episode: Int?

            switch activeMedia.contentRef {
            case let .movie(id):
                var descriptor = FetchDescriptor<Movie>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                let movie = try? modelContext.fetch(descriptor).first
                imdbId = movie?.imdbId
                season = nil
                episode = nil
            case let .episode(id):
                var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                let ep = try? modelContext.fetch(descriptor).first
                season = ep?.seasonNum
                episode = ep?.episodeNum
                imdbId = ep?.series?.imdbId
            default:
                imdbId = nil
                season = nil
                episode = nil
            }

            guard let imdbId, !imdbId.isEmpty else { return }

            do {
                let subtitleFile = try await OpenSubtitlesClient.shared.fetchBestSubtitle(
                    imdbId: imdbId,
                    season: season,
                    episode: episode
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    externalSubtitleURL = subtitleFile
                }
                Logger.player.info("[Subtitles] OpenSubtitles loaded for \(imdbId, privacy: .public)")
            } catch {
                Logger.player.debug("[Subtitles] OpenSubtitles: \(error.localizedDescription, privacy: .public)")
            }
        }
        .task {
            // Sample progress on a cadence and stash it in `WatchProgressBuffer`
            // (UserDefaults) rather than writing SwiftData. A background-context
            // save still forces the main context to merge and re-run every
            // `@Query` on `Movie`/`Episode`/`Series` (e.g. Home's continue-
            // watching rows) on the main thread — that merge is what hitched
            // KSPlayer every few seconds. Buffering triggers neither, so the only
            // periodic main-thread work is reading two clock values. The buffer
            // is flushed to SwiftData at safe boundaries (see `persistProgressDetached`).
            progressWriter = WatchProgressWriter(container: modelContext.container)
            // while !Task.isCancelled {
            //     try? await Task.sleep(for: .seconds(Self.progressSampleInterval))
            //     guard !Task.isCancelled else { break }
            //     bufferProgress()
            // }
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the foreground is a safe moment to flush; covers the user
            // backgrounding the app mid-playback without closing the player.
            if phase != .active { persistProgressDetached(force: true) }
            #if os(tvOS)
                // tvOS has no background playback for any engine, so a stream
                // left running behind the Home screen just keeps buffering and
                // holding the decoder. When the app actually leaves the
                // foreground, close the player so every engine tears its stream
                // down via `onDisappear`. `.inactive` is a transient transition
                // (a system overlay, the screensaver arming) where the app is
                // still foreground, so only act on a real `.background` move.
                if phase == .background { closePlayer() }
            #endif
        }
        .onDisappear {
            // Capture the clock synchronously, then flush off the main thread.
            persistProgressDetached(force: true)
            releaseAudioSession()
            seekBridge.reset()
            ContentIndexingService.shared.isPlaybackActive = false
        }
    }

    /// The media to hand the engine. For a directly playable stream (Xtream /
    /// m3u) this is `activeMedia` itself, so playback starts with no extra step.
    /// For a Stalker placeholder it is the resolved copy, gated on its identity
    /// matching the active stream so a stale resolution from the previous stream
    /// never reaches the engine during a channel/episode switch.
    private var displayMedia: PlayableMedia? {
        guard StalkerLink.isPlaceholder(activeMedia.url)
            || activeMedia.url.absoluteString.hasPrefix("stremio://")
        else { return activeMedia }
        guard let resolvedMedia, resolvedMedia.id == activeMedia.id else { return nil }
        return resolvedMedia
    }

    @ViewBuilder
    private var playerView: some View {
        if let media = displayMedia {
            engineView(for: media)
        } else if resolveError != nil {
            // Stalker `create_link` failed — surface the failure with a retry
            // rather than spinning forever.
            PlayerErrorIndicator(title: activeMedia.title, onRetry: retryResolve, onClose: closePlayer)
        } else {
            // Resolving the Stalker stream URL before the engine can load it.
            PlayerLoadingIndicator(title: activeMedia.title)
        }
    }

    @ViewBuilder
    private func engineView(for media: PlayableMedia) -> some View {
        // Keyed on the engine attempt so falling back tears the failed engine
        // down and builds the next one fresh, rather than reusing in-flight state.
        switch engine {
        case .avPlayer:
            AVPlayerEngineView(
                media: media,
                clock: clock,
                seekBridge: seekBridge,
                nextUpMedia: nextUpMedia,
                fallbackAvailable: hasFallbackEngine,
                onPlaybackFailed: fallBackToNextEngine,
                onSelectMedia: switchMedia
            )
            .id(engineAttempt)
        case .ksPlayer:
            KSPlayerEngineView(
                media: media,
                clock: clock,
                seekBridge: seekBridge,
                nextUpMedia: nextUpMedia,
                fallbackAvailable: hasFallbackEngine,
                onPlaybackFailed: fallBackToNextEngine,
                onSelectMedia: switchMedia
            )
            .id(engineAttempt)
        case .vlcKit:
            VLCPlayerEngineView(
                media: media,
                clock: clock,
                seekBridge: seekBridge,
                nextUpMedia: nextUpMedia,
                fallbackAvailable: hasFallbackEngine,
                onPlaybackFailed: fallBackToNextEngine,
                onSelectMedia: switchMedia
            )
            .id(engineAttempt)
        }
    }

    /// Resolves Stalker and Stremio placeholders into playable URLs. A no-op for
    /// directly playable streams. Re-runs whenever the active stream changes
    /// (open, channel surf, next episode), so each switch resolves a fresh,
    /// short-lived URL.
    private func resolveActiveMedia() async {
        let url = activeMedia.url
        if StalkerLink.isPlaceholder(url) {
            resolvedMedia = nil
            resolveError = nil
            do {
                resolvedMedia = try await StalkerStreamResolver.resolve(activeMedia, container: modelContext.container)
            } catch {
                resolveError = error.localizedDescription
                Logger.player.error("Stalker stream resolution failed: \(error.localizedDescription, privacy: .public)")
            }
        } else if url.absoluteString.hasPrefix("stremio://") {
            resolvedMedia = nil
            resolveError = nil
            do {
                // Fetch all available streams for the picker
                let options = try await StremioStreamResolver.fetchAllOptions(
                    for: activeMedia,
                    container: modelContext.container
                )
                if options.isEmpty {
                    throw StremioError.noCompatibleStreams
                }
                // If only one stream or user has auto-play enabled, play directly
                if options.count == 1 {
                    resolvedMedia = mediaWith(url: options[0].url)
                } else {
                    // Show picker — store options and present sheet
                    await MainActor.run {
                        stremioStreamOptions = options
                        showStreamPicker = true
                    }
                }
            } catch {
                resolveError = error.localizedDescription
                Logger.player.error("Stremio stream resolution failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func retryResolve() {
        engineAttempt = 0
        stremioStreamOptions = []
        showStreamPicker = false
        Task { await resolveActiveMedia() }
    }

    /// Creates a PlayableMedia copy with a resolved URL.
    private func mediaWith(url: URL) -> PlayableMedia {
        PlayableMedia(
            id: activeMedia.id,
            url: url,
            title: activeMedia.title,
            subtitle: activeMedia.subtitle,
            posterURL: activeMedia.posterURL,
            kind: activeMedia.kind,
            startTime: activeMedia.startTime,
            contentRef: activeMedia.contentRef
        )
    }

    /// Called when the user picks a stream from the Stremio picker sheet.
    private func selectStremioStream(_ option: StremioStreamOption) {
        showStreamPicker = false
        resolvedMedia = mediaWith(url: option.url)
    }

    /// Persist the outgoing stream's progress, then swap in a new one. The
    /// engine reconfigures its player when `activeMedia` changes.
    private func switchMedia(to newMedia: PlayableMedia) {
        guard newMedia.id != activeMedia.id else { return }
        // Flush the outgoing stream's progress before the clock resets — capture
        // happens synchronously inside `persistProgressDetached`.
        persistProgressDetached(force: true)
        clock.reset()
        // Restart the fallback chain from the primary engine for the new stream.
        engineAttempt = 0
        activeMedia = newMedia
        // Slide the outgoing channel into the recall slot so `right` can jump back.
        LiveChannelHistory.record(newMedia)
    }

    private var closeButton: some View {
        Button {
            persistProgressDetached(force: true)
            closePlayer()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(GlassFallback.thin, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(12)
        .accessibilityLabel("Close player")
        #if !os(tvOS)
            .keyboardShortcut(.escape, modifiers: [])
        #endif
    }

    private func closePlayer() {
        #if os(macOS)
            // Exit fullscreen first so the window animation is graceful, then close.
            if let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            dismissWindow(id: "player")
        #else
            dismiss()
        #endif
    }

    private func configureAudioSessionForPlayback() {
        #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .moviePlayback, options: [])
            try? session.setActive(true, options: [])
        #endif
    }

    private func releaseAudioSession() {
        #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    #if os(macOS)
        private func enterMacFullScreen() {
            // Wait for the window to mount before toggling fullscreen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard let window = NSApp.keyWindow ?? NSApp.windows.last(where: { $0.isVisible }) else { return }
                window.title = activeMedia.title
                if !window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                }
            }
        }
    #endif

    /// Seconds between progress samples. These only write `UserDefaults` now, so
    /// the cadence trades crash-recovery granularity against nothing meaningful.
    private static let progressSampleInterval: TimeInterval = 30

    /// Stash the current progress in `WatchProgressBuffer`. The only main-actor
    /// work is reading two `Double`s off the clock; the JSON + `UserDefaults`
    /// write is dispatched onto the buffer's background queue, so it can't stall
    /// KSPlayer's main-run-loop frame presentation. No SwiftData, no store merge,
    /// no `@Query` invalidation. Live streams carry no progress.
    private func bufferProgress() {
        guard !activeMedia.isLive else { return }
        WatchProgressBuffer.record(
            ref: activeMedia.contentRef,
            progress: clock.current,
            duration: clock.duration
        )
    }

    /// Commit the current progress to SwiftData off the main thread. Called only
    /// at boundaries (close, episode switch, app backgrounding) where the one
    /// resulting store merge can't disturb playback. Captures the clock
    /// synchronously *before* awaiting, so a subsequent `clock.reset()` can't
    /// race the read; clears the buffer entry once the write lands.
    private func persistProgressDetached(force: Bool) {
        guard let writer = progressWriter else { return }
        if activeMedia.isLive, !force { return }
        let ref = activeMedia.contentRef
        let now = clock.current
        let total = clock.duration
        Task { @MainActor in
            let completion = await writer.record(
                ref: ref, progress: now, duration: total, force: force
            )
            WatchProgressBuffer.remove(ref: ref)
            if let completion { syncTraktWatched(ref: completion.ref) }
        }
    }

    /// One-time "watched" sync on Trakt. Runs at most once per title (when it
    /// crosses 90%), so the main-context fetch here is off the playback hot path.
    /// `TraktService` is `@MainActor`, hence this stays on the main actor.
    private func syncTraktWatched(ref: PlayableMedia.ContentRef) {
        switch ref {
        case let .movie(id):
            var descriptor = FetchDescriptor<Movie>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let movie = try? modelContext.fetch(descriptor).first else { return }
            TraktService.shared.syncWatched(movie: movie, watched: true)
        case let .episode(id):
            var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let episode = try? modelContext.fetch(descriptor).first else { return }
            TraktService.shared.syncWatched(episode: episode, watched: true)
        case .live:
            break
        }
    }
}

#Preview {
    FullScreenPlayerView(media: PlayableMedia(
        id: "preview",
        url: URL(string: "https://example.com/stream.m3u8")!,
        title: "Sample Stream",
        subtitle: nil,
        posterURL: nil,
        kind: .live,
        startTime: 0,
        contentRef: .live("preview")
    ))
    .preferredColorScheme(.dark)
}
