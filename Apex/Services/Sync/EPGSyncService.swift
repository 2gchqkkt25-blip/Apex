//
//  EPGSyncService.swift
//  Apex
//
//  Owns the background EPG refresh task and publishes whether one is running,
//  for the EPG settings screen. Singleton because it must outlive any one view
//  and be reachable from launch, the content-sync completion hook, and the
//  manual "Sync Now" button.
//

import Combine
import Foundation
import Network
import Observation
import OSLog
import SwiftData

/// Prevents the content indexer from competing with a heavy XMLTV parse that is
/// writing into the same catalog container. Gate is only for heavy XMLTV parse —
/// never for Xtream per-channel API sync.
enum EPGSyncGate {
    nonisolated(unsafe) static var isActive = false
}

@Observable
final class EPGSyncService {
    static let shared = EPGSyncService()

    @MainActor private(set) var isSyncing = false
    @MainActor private(set) var refreshGeneration = 0
    @MainActor private(set) var syncProgress: Double?
    @MainActor private(set) var syncProgressLabel: String?

    @MainActor private var lastGuideRefreshSignal = Date.distantPast
    private static let minGuideRefreshInterval: TimeInterval = 5
    /// Throttle mid-sync guide reloads hard: each bump forces every EPG-observing
    /// view to re-run main-thread SwiftData fetches while the store is being
    /// written. At 5s this thrashed the UI (jank / watchdog kills on tvOS).
    private static let minGuideRefreshDuringSyncInterval: TimeInterval = 20

    private var container: ModelContainer?
    private var task: Task<Void, Never>?

    /// True while a playlist sync (content + its inline guide step) owns the
    /// catalog store. Background `syncIfDue`/`syncNow` triggers must NOT start a
    /// second, concurrent EPG sync during this window — stacking a full 14-feed
    /// refresh on top of a large content sync is what pushed the app over the
    /// memory limit (~18% in, on both iOS and tvOS). Set by `SyncProgressView`
    /// for the entire sync flow.
    nonisolated(unsafe) private var exclusiveSyncOwners = 0

    static let syncTimeout: TimeInterval = 3_600
    /// A guide refresh bundled into a playlist sync must not hold the sync sheet
    /// open indefinitely — cap it and let any remaining feeds finish in the
    /// background low-priority pass.
    static let bundledSyncTimeout: TimeInterval = 240

    private static let poisonedStoreResetKey = "epg.store.reset.noAlignV1"

    private init() {}

    func configure(container: ModelContainer) {
        self.container = container
        resetPoisonedStoreIfNeeded(container: container)
    }

    /// One-time wipe of the EPGListing store on upgrade from the old alignment
    /// era. Those rows have fabricated timestamps that will never match real
    /// airings. After this runs once, the key stays set and it's a no-op.
    private func resetPoisonedStoreIfNeeded(container: ModelContainer) {
        let key = Self.poisonedStoreResetKey
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            try context.delete(model: EPGListing.self)
            try context.save()
            Logger.database.warning("EPG poisoned store reset complete (one-time wipe)")
        } catch {
            Logger.database.error("EPG poisoned store reset failed: \(error.localizedDescription)")
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Bumps `refreshGeneration` so views reload guide data, throttled to at
    /// most once per 60 seconds to avoid over-reloading during background
    /// prefetch.
    @MainActor func signalGuideRefresh() {
        signalGuideRefresh(minInterval: Self.minGuideRefreshInterval)
    }

    /// Throttled guide reload while a sync is in flight — lets the grid and
    /// channel cards pick up each external feed without waiting for all 14.
    @MainActor func signalGuideRefreshDuringSync() {
        signalGuideRefresh(minInterval: Self.minGuideRefreshDuringSyncInterval)
    }

    @MainActor func updateSyncProgress(fraction: Double?, label: String?) {
        syncProgress = fraction
        syncProgressLabel = label
    }

    @MainActor func forceGuideRefresh() {
        lastGuideRefreshSignal = .distantPast
        refreshGeneration += 1
    }

    @MainActor private func signalGuideRefresh(minInterval: TimeInterval) {
        let now = Date()
        guard now.timeIntervalSince(lastGuideRefreshSignal) >= minInterval else { return }
        lastGuideRefreshSignal = now
        refreshGeneration += 1
    }

    /// Marks the start of a playlist sync so background EPG triggers are
    /// suppressed until it finishes. Balanced with `endExclusiveSync()`.
    @MainActor func beginExclusiveSync() {
        exclusiveSyncOwners += 1
        // A background refresh may already be running (launch `syncIfDue` fires
        // on a timer). Stop it so it doesn't run concurrently with the content
        // sync — the playlist sync will refresh the guide itself.
        cancelActiveSync(reason: "playlist sync taking priority")
    }

    @MainActor func endExclusiveSync() {
        exclusiveSyncOwners = max(0, exclusiveSyncOwners - 1)
    }

    /// Manual trigger (settings "Sync Now"): refreshes now regardless of the
    /// schedule.
    func syncNow() {
        Logger.database.warning("EPG sync triggered (manual)")
        // Manual refresh: the user explicitly asked for fresh data, so drop the
        // on-demand browse cache too.
        kick(invalidateLiveCache: true)
    }

    /// Deferred, low-priority guide refresh using the lighter bundled feed set
    /// (US feeds, excludes the giant `US_LOCALS1`). Used on Apple TV so the guide
    /// import runs *after* the content-sync sheet finishes and its memory is
    /// released — parsing a large feed on top of the content sync's resident
    /// memory jetsams the app on tvOS's tight budget.
    func syncBundledInBackground() {
        Logger.database.warning("EPG sync triggered (deferred bundled)")
        // Background/deferred refresh: keep the on-demand browse cache warm so
        // switching Live TV categories stays instant while the guide fills in.
        kick(mode: .withPlaylist, invalidateLiveCache: false)
    }

    /// Runs a full guide refresh and suspends until it finishes. Used when
    /// bundled with a playlist sync so content + EPG update in one flow.
    func syncAwaiting(
        container: ModelContainer,
        mode: EPGSyncMode = .withPlaylist,
        onProgress: (@MainActor @Sendable (Double?, String?) -> Void)? = nil
    ) async -> Bool {
        cancelActiveSync(reason: "replaced by awaited sync")

        await MainActor.run {
            isSyncing = true
            syncProgress = nil
            syncProgressLabel = nil
        }

        defer {
            Task { @MainActor in
                isSyncing = false
                syncProgress = nil
                syncProgressLabel = nil
                try? await Task.sleep(for: .milliseconds(500))
                refreshGeneration += 1
            }
        }

        await EPGLiveLoader.shared.invalidateAll()
        ContentIndexingService.shared.prepareForEPGSync()
        defer { ContentIndexingService.shared.epgSyncFinished() }

        let manager = EPGSyncManager(modelContainer: container)
        let timeout: TimeInterval
        switch mode {
        case .tvOSQuick: timeout = 120  // Only 3 small feeds — 2 min cap
        case .withPlaylist: timeout = Self.bundledSyncTimeout
        case .full: timeout = Self.syncTimeout
        }
        do {
            let succeeded = try await Self.runWithTimeout(seconds: timeout) {
                await manager.syncAllSources(mode: mode) { completed, total in
                    let fraction = total > 0 ? Double(completed) / Double(total) : nil
                    let formatter = NumberFormatter()
                    formatter.numberStyle = .decimal
                    let completedStr = formatter.string(from: NSNumber(value: completed)) ?? "\(completed)"
                    let totalStr = formatter.string(from: NSNumber(value: total)) ?? "\(total)"
                    let label = "\(completedStr) / \(totalStr) channels"
                    Task { @MainActor in
                        EPGSyncService.shared.updateSyncProgress(fraction: fraction, label: label)
                        onProgress?(fraction, label)
                    }
                }
            }
            if succeeded {
                await MainActor.run { EPGSyncSchedule.lastSyncDate = Date() }
            }
            EPGSyncManager.recoverInterruptedSyncs(in: ModelContext(container))
            Logger.database.info("EPG awaited refresh finished (success: \(succeeded))")
            return succeeded
        } catch {
            Logger.database.warning("EPG awaited sync error/timeout: \(error.localizedDescription, privacy: .public)")
            EPGSyncManager.recoverInterruptedSyncs(in: ModelContext(container))
            return false
        }
    }

    /// Background trigger (launch / after a content sync): refreshes only if the
    /// guide is stale per the EPG frequency setting.
    func syncIfDue() {
        // Background guide refresh only on Wi‑Fi — 8–14 XMLTV feeds are too heavy
        // for cellular and compete with browse/playback on constrained links.
        guard NetworkMonitor.shared.shouldProceedWithHeavyNetworkWork() else { return }
        let raw = UserDefaults.standard.string(forKey: SyncFrequency.epgStorageKey) ?? ""
        let frequency = SyncFrequency.resolveEPG(raw)
        guard frequency.isDue(lastSyncDate: EPGSyncSchedule.lastSyncDate) else { return }
        // A silent background refresh must never run the full 14-feed pass —
        // that includes the ~500MB `US_LOCALS1` feed, which `urlsForBundledSync()`
        // excludes outright (see its doc comment: "drove memory warnings even on
        // iPhone"). This used to be tvOS-only (tight jetsam headroom); on iOS
        // the `.full` default here let an unattended `syncIfDue()` download and
        // parse that feed while the user was actively using the app, ballooning
        // memory past the entitled hard limit and triggering a fatal jetsam
        // kill. Only an explicit Settings -> Sync Now (`syncNow()`) should ever
        // run the full pass — the user has then consciously opted into a longer
        // sync.
        kick(mode: .withPlaylist, invalidateLiveCache: false)
    }

    private func kick(mode: EPGSyncMode = .full, invalidateLiveCache: Bool = true) {
        guard let container else {
            Logger.database.error("EPG sync skipped — container not configured")
            return
        }
        // A playlist sync owns the store and runs its own guide step — never
        // start a second concurrent EPG refresh on top of it.
        guard exclusiveSyncOwners == 0 else {
            Logger.database.info("EPG sync suppressed — playlist sync in progress")
            return
        }
        // Coalesce: if a refresh is already in flight, let it finish rather than
        // cancelling and restarting. Cancel-and-restart caused every download to
        // fail with `URLError.cancelled` whenever a second trigger fired (launch
        // `syncIfDue` + a manual Sync Now, etc.), leaving the guide unpopulated.
        // Only an explicit `cancelActiveSync` (user abort / playlist takeover)
        // stops an in-flight sync.
        guard task == nil else {
            Logger.database.info("EPG sync already running — coalescing trigger")
            return
        }
        startSync(container: container, mode: mode, invalidateLiveCache: invalidateLiveCache)
    }

    func cancelActiveSync(reason: String) {
        Logger.database.warning("EPG sync cancelled: \(reason, privacy: .public)")
        task?.cancel()
        task = nil
    }

    private func startSync(
        container: ModelContainer,
        mode: EPGSyncMode = .full,
        invalidateLiveCache: Bool = true
    ) {
        let syncContainer = container
        let syncMode = mode
        let shouldInvalidateLiveCache = invalidateLiveCache
        task = Task { @MainActor in
            isSyncing = true
            syncProgress = nil
            syncProgressLabel = nil

            defer {
                // Clear the handle so `kick()`'s coalescing guard allows the next
                // scheduled/manual refresh to start. Without this the guard would
                // see a non-nil (finished) task forever and never sync again.
                self.task = nil
                EPGSyncManager.recoverInterruptedSyncs(in: ModelContext(syncContainer))
                Task { @MainActor in
                    isSyncing = false
                    syncProgress = nil
                    syncProgressLabel = nil
                    try? await Task.sleep(for: .milliseconds(500))
                    refreshGeneration += 1
                }
            }

            // Only wipe the on-demand browse cache for an explicit manual
            // refresh. Background/deferred/scheduled syncs must keep it warm —
            // clearing it forced every Live TV category switch to re-fetch each
            // channel over the network (the multi-minute "data disappeared"
            // waits on tvOS). The store, refreshed by this sync, still takes
            // precedence on the next guide reload.
            if shouldInvalidateLiveCache {
                await EPGLiveLoader.shared.invalidateAll()
            }

            ContentIndexingService.shared.prepareForEPGSync()
            defer { ContentIndexingService.shared.epgSyncFinished() }

            let manager = EPGSyncManager(modelContainer: syncContainer)
            let timeout: TimeInterval
            switch syncMode {
            case .tvOSQuick: timeout = 120
            case .withPlaylist: timeout = Self.bundledSyncTimeout
            case .full: timeout = Self.syncTimeout
            }
            let succeeded: Bool
            do {
                succeeded = try await Self.runWithTimeout(seconds: timeout) {
                    await manager.syncAllSources(mode: syncMode) { [weak self] completed, total in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            let progress = total > 0 ? Double(completed) / Double(total) : nil
                            self.syncProgress = progress
                            let formatter = NumberFormatter()
                            formatter.numberStyle = .decimal
                            let completedStr = formatter.string(from: NSNumber(value: completed)) ?? "\(completed)"
                            let totalStr = formatter.string(from: NSNumber(value: total)) ?? "\(total)"
                            self.syncProgressLabel = "\(completedStr) / \(totalStr) channels"
                        }
                    }
                }
            } catch {
                Logger.database.warning("EPG sync error/timeout: \(error.localizedDescription, privacy: .public)")
                succeeded = false
            }

            if succeeded {
                EPGSyncSchedule.lastSyncDate = Date()
            }
            Logger.database.info("EPG refresh finished (success: \(succeeded))")
        }
    }

    /// Races `body` against a timeout. Throws `CancellationError` if the timeout
    /// fires first.
    private static func runWithTimeout<T: Sendable>(
        seconds: TimeInterval,
        body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await body()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CancellationError()
            }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
        }
    }
}

// MARK: - NetworkMonitor

/// Lightweight connectivity observer so background network work (EPG sync,
/// content indexing) can pause when the network is unavailable instead of
/// letting every deferred task fail at once — a failure storm that can push
/// a device with a large library over the jetsam limit.
///
/// Lives here (rather than a standalone file) because this is the primary
/// consumer and both EPG + indexing services reference it.
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected: Bool = true
    /// True on cellular or other expensive interfaces.
    @Published private(set) var isExpensive: Bool = false
    /// True when Low Data Mode is enabled.
    @Published private(set) var isConstrained: Bool = false
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.streaminfinity.apex.network-monitor")

    /// Defaults to `true` so the app doesn't block itself before the first
    /// path update arrives (which is async and may take a moment).
    var isDisconnected: Bool { !isConnected }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let expensive = path.isExpensive
            let constrained = path.isConstrained
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasConnected = self.isConnected
                let wasExpensive = self.isExpensive
                self.isConnected = connected
                self.isExpensive = expensive
                self.isConstrained = constrained
                if wasConnected && !connected {
                    Logger.network.warning("[NetworkMonitor] Connectivity lost — pausing background network work")
                } else if !wasConnected && connected {
                    Logger.network.info("[NetworkMonitor] Connectivity restored — resuming background network work")
                    ContentIndexingService.shared.kick(after: .seconds(30))
                } else if wasExpensive && !expensive && !constrained && connected {
                    Logger.network.info("[NetworkMonitor] Wi‑Fi restored — resuming deferred indexing")
                    ContentIndexingService.shared.kick(after: .seconds(60))
                }
                if expensive || constrained {
                    Logger.network.info("[NetworkMonitor] Expensive/constrained path — deferring heavy background work")
                }
            }
        }
        monitor.start(queue: queue)
    }

    /// Returns `true` if the caller should proceed; `false` if the network is
    /// down and the work should be deferred until connectivity returns.
    func shouldProceedWithNetworkWork() -> Bool {
        guard isConnected else {
            Logger.network.info("[NetworkMonitor] Skipping network work — offline")
            return false
        }
        return true
    }

    /// Like `shouldProceedWithNetworkWork`, but also blocks on cellular and
    /// Low Data Mode. Used for background TMDB indexing and deferred EPG sync —
    /// not for user-initiated playlist sync or playback.
    func shouldProceedWithHeavyNetworkWork() -> Bool {
        guard shouldProceedWithNetworkWork() else { return false }
        guard !isExpensive, !isConstrained else {
            Logger.network.info("[NetworkMonitor] Skipping heavy network work — cellular or constrained")
            return false
        }
        return true
    }
}
