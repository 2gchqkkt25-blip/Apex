//
//  ContentIndexingService.swift
//  Apex
//
//  Owns the background ContentIndexer task and publishes its status for the
//  Settings screen. Singleton because it must outlive any one view and be
//  reachable from the player (to pause indexing during playback) and from the
//  sync flow (to kick a pass after new content arrives).
//

import Foundation
import Observation
import OSLog
import SwiftData

@Observable
final class ContentIndexingService {
    static let shared = ContentIndexingService()

    enum State: Equatable {
        /// Not yet configured or never kicked.
        case idle
        /// Downloading/loading the embedding model.
        case preparing
        case indexing
        /// A playlist sync or playback is active; indexing resumes on its own.
        case waiting
        case upToDate
        /// The embedding model cannot be loaded on this device.
        case unavailable
        /// The last pass ended early (e.g. offline); the next kick retries.
        case interrupted
    }

    private(set) var state: State = .idle
    private(set) var indexedCount = 0
    private(set) var totalCount = 0

    /// Set by the player while the full-screen player is up. The indexer
    /// polls this and pauses: even background-context saves force a
    /// main-context merge that re-runs every @Query and hitches KSPlayer.
    var isPlaybackActive = false

    /// Set by `CloudSyncCoordinator` while `NSPersistentCloudKitContainer` is
    /// mid import/export. The indexer pauses then: CloudKit tears down and
    /// re-adds stores on the coordinator shared by the multi-store container,
    /// and faulting a catalog object during that window throws an uncatchable
    /// `no such table` `NSException`.
    var isCloudSyncActive = false

    /// Brief pause while the user is switching tabs so chunk saves don't
    /// re-run every mounted tab's `@Query` mid-transition.
    private var browsePauseUntil: Date?

    var isBrowsePaused: Bool {
        guard let until = browsePauseUntil else { return false }
        if until > Date() { return true }
        browsePauseUntil = nil
        return false
    }

    /// Holds indexing back while browse surfaces mount and paint.
    func pauseForBrowse(duration: Duration = .seconds(10)) {
        browsePauseUntil = Date().addingTimeInterval(TimeInterval(duration.components.seconds))
    }

    private var container: ModelContainer?
    private var task: Task<Void, Never>?

    private init() {}

    func configure(container: ModelContainer) {
        self.container = container
    }

    /// Starts a background indexing pass unless one is already running.
    /// Called on launch and after every successful playlist sync, so missing
    /// indexes are picked up without any user action.
    ///
    /// `delay` lets the post-sync caller hold the pass off briefly: a sync just
    /// grew the catalog and the user is about to browse it, so loading the
    /// embedding model and the per-chunk saves (each forces a main-context merge
    /// that re-runs every `@Query`) shouldn't fight that first browse. `task` is
    /// claimed immediately, so a second kick during the delay coalesces to a no-op.
    func kick(after delay: Duration = .zero) {
        guard let container, task == nil else { return }
        guard !EPGSyncGate.isActive else { return }
        // Skip on offline, cellular, or Low Data Mode — TMDB indexing is
        // hundreds of requests that can crash a large-library device on cell.
        guard NetworkMonitor.shared.shouldProceedWithHeavyNetworkWork() else { return }
        // Older builds could leave `.unavailable` after an embedding-model error even
        // though TMDB enrichment no longer depends on it — don't block forever.
        if state == .unavailable { state = .idle }
        let indexer = ContentIndexer(modelContainer: container)
        task = Task {
            defer { task = nil }
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            do {
                try await indexer.run(status: self)
            } catch is CancellationError where EPGSyncGate.isActive {
                Logger.indexing.debug("Indexing paused for EPG sync")
                state = .waiting
            } catch is CancellationError {
                state = .interrupted
            } catch let error as URLError where error.code == .cancelled && EPGSyncGate.isActive {
                Logger.indexing.debug("Indexing paused for EPG sync")
                state = .waiting
            } catch is TextEmbedder.EmbedderError {
                state = .interrupted
                Logger.indexing.warning("Embedding model error — TMDB indexing will retry on next kick")
            } catch {
                state = .interrupted
                Logger.indexing.error("Indexing pass interrupted: \(error)")
            }
        }
    }

    /// Cancels any in-flight pass so a full XMLTV refresh owns the catalog store.
    func prepareForEPGSync() {
        EPGSyncGate.isActive = true
        task?.cancel()
        task = nil
        if state == .indexing || state == .preparing {
            state = .waiting
        }
    }

    /// Resumes background indexing after guide import finishes.
    func epgSyncFinished() {
        EPGSyncGate.isActive = false
        kick(after: .seconds(45))
    }

    #if DEBUG
        /// DEBUG-only: cancels any in-flight pass and clears progress so the
        /// status reflects a freshly-wiped index. Pair with
        /// `StorageManager.clearIndex` then `kick()` to rebuild from scratch.
        func reset() {
            task?.cancel()
            task = nil
            if state != .unavailable {
                state = .idle
            }
            indexedCount = 0
            totalCount = 0
        }
    #endif

    // MARK: - Progress (called by ContentIndexer)

    func setPreparing() {
        state = .preparing
    }

    func setWaiting() {
        state = .waiting
    }

    func update(indexed: Int, total: Int) {
        indexedCount = indexed
        totalCount = total
        state = .indexing
    }

    func finish(indexed: Int, total: Int) {
        indexedCount = indexed
        totalCount = total
        state = .upToDate
    }
}

// MARK: - Settings status text

extension ContentIndexingService {
    /// One-line status for the Settings screen.
    var statusText: LocalizedStringResource {
        switch state {
        case .idle:
            "Not started"
        case .preparing:
            "Preparing…"
        case .indexing:
            "Indexed \(indexedCount) of \(totalCount) titles"
        case .waiting:
            "Paused"
        case .upToDate:
            totalCount > 0 ? "Up to date — \(totalCount) titles" : "Up to date"
        case .unavailable:
            "Not available on this device"
        case .interrupted:
            "Interrupted — will retry later"
        }
    }
}
