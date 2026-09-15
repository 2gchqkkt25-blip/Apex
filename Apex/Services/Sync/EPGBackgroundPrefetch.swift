//
//  EPGBackgroundPrefetch.swift
//  Apex
//
//  Continues filling the guide store after Sync Now returns, without blocking
//  the UI or holding the sync timeout window open.
//

import Foundation
import OSLog
import SwiftData

actor EPGBackgroundPrefetch {
    static let shared = EPGBackgroundPrefetch()

    private var task: Task<Void, Never>?
    private var activeBrowsers = 0
    private static let batchSize = 150
    private static let pauseBetweenBatches: TimeInterval = 1.5

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Pause background prefetch while on-demand browse is fetching visible channels.
    func setBrowseActive(_ active: Bool) {
        activeBrowsers = max(0, activeBrowsers + (active ? 1 : -1))
    }

    private func waitWhileBrowseActive() async {
        while !Task.isCancelled {
            let playbackActive = await MainActor.run { ContentIndexingService.shared.isPlaybackActive }
            if activeBrowsers == 0, !playbackActive { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Prefetch remaining channels after the blocking prime slice finishes.
    func schedule(
        credentials: EPGPlaylistCredentials,
        identities: [some EPGChannelIdentity],
        startIndex: Int,
        container: ModelContainer
    ) {
        guard credentials.sourceType == .xtream else { return }
        guard startIndex < identities.count else { return }

        task?.cancel()
        let remaining = Array(identities.dropFirst(startIndex))
        Logger.database.warning(
            "EPG background prefetch — \(remaining.count) channels after index \(startIndex)"
        )

        task = Task(priority: .utility) {
            let client = XtreamClient(urlSession: XtreamClient.makeEPGBulkSyncSession())
            var offset = 0
            while offset < remaining.count {
                if Task.isCancelled { return }
                await self.waitWhileBrowseActive()
                if Task.isCancelled { return }
                let end = min(offset + Self.batchSize, remaining.count)
                let batch = Array(remaining[offset ..< end])
                _ = await EPGAPISync.sync(
                    credentials: credentials,
                    identities: batch,
                    container: container,
                    client: client,
                    concurrencyLimit: 3,
                    beforeRequest: { await self.waitWhileBrowseActive() }
                )
                offset = end
                await MainActor.run {
                    EPGSyncService.shared.signalGuideRefresh()
                }
                if offset < remaining.count {
                    try? await Task.sleep(for: .seconds(Self.pauseBetweenBatches))
                }
            }
            Logger.database.warning("EPG background prefetch complete — \(remaining.count) channels")
        }
    }
}
