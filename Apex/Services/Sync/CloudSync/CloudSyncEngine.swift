import Foundation
import OSLog
import SwiftData

/// Outcome of one reconcile pass — surfaced to the coordinator for status and
/// logging. Purely informational.
nonisolated struct CloudSyncReconcileResult: Equatable {
    var playlistsPushed = 0
    var playlistsPulled = 0
    var playlistsCreatedLocally = 0
    /// Playlist UUIDs materialised from iCloud on this pass. The auto-sync cover
    /// uses these so a Sync Now on one device does not pop the progress UI on
    /// the others.
    var importedPlaylistIDs: Set<UUID> = []
    var contentPushed = 0
    var contentPulled = 0
    var epgSourcesPushed = 0
    var epgSourcesPulled = 0
    var mediaServersPushed = 0
    var mediaServersPulled = 0
    var mediaServersCreatedLocally = 0
    /// Cloud states whose local catalog item hasn't synced yet — left pending
    /// (shadow untouched) so a later pass applies them once the catalog lands.
    var contentPending = 0
    /// Set when the pass was aborted because the local catalog store was
    /// unreadable (a fetch threw — a transient `no such table` detach or a
    /// corrupt store). No stores or shadow were touched; a later pass retries.
    var skippedUntrustworthyLocalStore = false
    /// Set when the local catalog came up empty after previously holding data (a
    /// lost or recreated `default.store`): the stale shadow was dropped so this
    /// pass pulls the surviving cloud records back instead of pushing deletions.
    var recoveredFromEmptyLocalStore = false
    /// Set when the CloudKit mirror was unreadable. No stores or shadow were
    /// touched; a later pass retries once the mirror is readable again.
    var skippedUntrustworthyCloudMirror = false
    /// Set when the mirror came up entirely empty while the shadow still held
    /// baselines (typically a CloudKit import that hadn't landed yet): the stale
    /// shadow was dropped so this pass re-publishes local content rather than
    /// deleting it.
    var recoveredFromEmptyCloudMirror = false
}

/// A local catalog item paired with its current syncable state, gathered up-front
/// so a reconcile pass touches the store once per type. `nonisolated` so the
/// engine actor can hold and read it off the main actor (the project defaults to
/// main-actor isolation, which would otherwise isolate this struct's members).
/// Not `private`: the profile operations in `CloudSyncEngine+Profiles.swift`
/// read its `kind` / `values`.
nonisolated struct LocalContentEntry {
    let values: ContentStateValues
    let kind: SyncedContentKind
    let model: any PersistentModel
}

/// Reconciles local SwiftData (the catalog + playlists) with the CloudKit-synced
/// mirror models (`SyncedPlaylist`, `UserContentState`) using the three-way
/// merge in `CloudSyncMerge`.
///
/// An `actor` that owns background `ModelContext`s — one per store, the same
/// pattern as `ContentSyncManager` / `WatchProgressWriter` — so all store work
/// stays off the main thread. Saves on these contexts auto-merge into their
/// container's main context, so `@Query`-driven UI updates after a pull, and a
/// newly pulled playlist trips `MainTabView`'s auto-sync to fetch its catalog.
///
/// Two contexts because the catalog and the CloudKit mirrors now live in separate
/// containers (so CloudKit's churn can't invalidate catalog `@Query`s). Each store
/// op routes to its own context; a reconcile saves both, then persists the shadow.
actor CloudSyncEngine {
    /// The local-only catalog store (Playlist, Movie, Series, Episode, LiveStream).
    /// Replaced wholesale by `releaseHydratedRows()` between operations, so read
    /// it fresh per use rather than caching it across a suspension point.
    private(set) var catalogContext: ModelContext
    /// The CloudKit-mirrored store (SyncedPlaylist, UserContentState, UserProfile).
    private(set) var cloudContext: ModelContext
    let shadow: CloudSyncShadow

    /// Retained so `releaseHydratedRows()` can rebuild the contexts above.
    private let catalogContainer: ModelContainer
    private let cloudContainer: ModelContainer
    /// True for the DEBUG single-container init, where both store roles share one
    /// context; the rebuild has to preserve that or tests would see the catalog
    /// and mirror halves of a pass land in two contexts that never merge.
    private let sharesOneContext: Bool

    /// The profile whose state the catalog currently projects. Read from
    /// `ActiveProfileStore` at the start of each reconcile, so content state is
    /// pushed to / pulled from only this profile's mirror records; other
    /// profiles' records sync via CloudKit untouched until they become active.
    /// Not `private`: `CloudSyncEngine+Fetch.swift` reads it (`fetchContentMirrors`).
    var activeProfileID = UserProfile.defaultProfileID

    init(catalogContainer: ModelContainer, cloudContainer: ModelContainer, shadow: CloudSyncShadow = CloudSyncShadow()) {
        self.catalogContainer = catalogContainer
        self.cloudContainer = cloudContainer
        sharesOneContext = false
        catalogContext = Self.makeContext(catalogContainer)
        cloudContext = Self.makeContext(cloudContainer)
        self.shadow = shadow
    }

    private static func makeContext(_ container: ModelContainer) -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    #if DEBUG
        /// Test/preview convenience: one container holding every model, shared by
        /// both store roles via a single background context — exactly the pre-split
        /// behavior. Production uses the two-container designated init above so
        /// CloudKit's churn can't invalidate the catalog; the reconcile/merge logic
        /// the tests exercise routes identically either way.
        init(container: ModelContainer, shadow: CloudSyncShadow = CloudSyncShadow()) {
            catalogContainer = container
            cloudContainer = container
            sharesOneContext = true
            let ctx = Self.makeContext(container)
            catalogContext = ctx
            cloudContext = ctx
            self.shadow = shadow
        }
    #endif

    /// Run a full bidirectional reconcile: playlists first (so content can scope
    /// to the resulting live playlists), then per-content user state. Persists the
    /// shadow baseline and saves both stores at the end.
    @discardableResult
    func reconcile() -> CloudSyncReconcileResult {
        activeProfileID = ActiveProfileStore.current ?? UserProfile.defaultProfileID
        var result = CloudSyncReconcileResult()

        switch localCatalogReadiness() {
        case .ready:
            break
        case .unreadable:
            // The store is mid-detach or corrupt. Trust nothing: skip without
            // touching either store or the shadow, and retry on a later pass.
            result.skippedUntrustworthyLocalStore = true
            return result
        case .emptiedButHadData:
            // The catalog file was lost or recreated empty while the cloud and
            // the shadow survived. Drop the stale baseline so the merge below
            // pulls the surviving cloud records back into the catalog instead of
            // reading their absent local counterparts as deletions and wiping
            // every device. With an empty shadow every verdict is a pull — a
            // cloud-mirror deletion (`pushToCloud(nil)`) is now impossible.
            Logger.sync.error("Local catalog empty but shadow had baselines — recovering from cloud, dropping stale shadow (no deletions pushed)")
            shadow.reset()
            result.recoveredFromEmptyLocalStore = true
        }

        switch cloudMirrorReadiness() {
        case .ready:
            break
        case .unreadable:
            result.skippedUntrustworthyCloudMirror = true
            return result
        case .emptyButHadData:
            // Symmetric to `.emptiedButHadData` above, and for the same reason:
            // drop the stale baseline so every verdict this pass becomes a push
            // rather than a deletion. Local content is then re-published to the
            // mirror instead of being destroyed by an import that simply hadn't
            // arrived yet. Safe in both directions — the mirror is empty, so
            // there is nothing there for a push to overwrite.
            Logger.sync.error("Cloud mirror empty but shadow had baselines — re-publishing local content instead of applying deletions")
            shadow.reset()
            result.recoveredFromEmptyCloudMirror = true
        }

        defer { releaseHydratedRows() }
        do {
            // Collapse any duplicate default profile a freshly-synced device
            // imported before its own bootstrap-created one could converge.
            try reconcileProfiles()
            let livePlaylistPrefixes = try reconcilePlaylists(into: &result)
            let liveMediaServerPrefixes = try reconcileMediaServers(into: &result)
            try reconcileContent(
                livePrefixes: livePlaylistPrefixes.union(liveMediaServerPrefixes),
                into: &result
            )
            // Manual EPG sources sync as their own lightweight mirror; each
            // playlist's derived (linked) source is regenerated locally so it
            // appears on every device that has the playlist.
            try reconcileEPGSources(into: &result)
            regenerateLinkedEPGSources()
            // Two stores → two saves (`saveStores`, catalog first). Persist the
            // shadow only after both succeed, so a half-applied pass is never
            // baselined: if either save throws we fall to the catch, leave the
            // shadow untouched, and the next pass re-derives and re-applies (the
            // 3-way merge is idempotent).
            try saveStores()
            shadow.persist()
            Logger.sync.info("Reconcile pl +\(result.playlistsPushed) new \(result.playlistsCreatedLocally) ms +\(result.mediaServersPushed)/\(result.mediaServersPulled)/new \(result.mediaServersCreatedLocally) ct +\(result.contentPushed)/\(result.contentPulled) pend \(result.contentPending) epg +\(result.epgSourcesPushed)/\(result.epgSourcesPulled)") // swiftlint:disable:this line_length
        } catch {
            Logger.sync.error("Reconcile failed: \(error.localizedDescription)")
        }
        return result
    }

    /// Drops every row the just-finished operation hydrated from both contexts.
    ///
    /// The contexts are created once and live for the whole process, so without
    /// this each operation's rows stay in their identity maps indefinitely. A
    /// reconcile pass touches all synced user state plus the catalog rows behind
    /// it, and passes re-run on every playlist-sync completion — so on a large
    /// catalog the maps grow without bound across a browsing session, which is
    /// enough to walk a 2 GB Apple TV into jetsam with no playback involved.
    ///
    /// Safe on both outcomes: after a successful `saveStores()` nothing is
    /// pending, and after a failed one the shadow is left untouched and the
    /// three-way merge is idempotent, so dropping the half-applied changes is
    /// exactly what the retrying pass expects. Callers must therefore not read
    /// fetched models afterwards — every operation here returns value types.
    /// `ModelContext` exposes no `reset()`, so the contexts are rebuilt instead —
    /// dropping the old ones releases everything they had hydrated.
    func releaseHydratedRows() {
        catalogContext = Self.makeContext(catalogContainer)
        cloudContext = sharesOneContext ? catalogContext : Self.makeContext(cloudContainer)
    }

    /// Persist pending changes in both stores, catalog first so a pulled cloud
    /// change lands locally before its mirror state is acknowledged. Callers that
    /// also persist the shadow must do so only after this returns without throwing.
    func saveStores() throws {
        if catalogContext.hasChanges { try catalogContext.save() }
        if cloudContext.hasChanges { try cloudContext.save() }
    }

    // MARK: - Content state

    private func reconcileContent(livePrefixes: Set<String>, into result: inout CloudSyncReconcileResult) throws {
        var mirrors = try fetchContentMirrors()
        var localValues = try fetchLocalContentValues()

        var ids = Set(mirrors.keys).union(localValues.keys)
        ids.formUnion(shadow.contentShadowIDs())

        rematchOrphanedContent(
            mirrors: &mirrors,
            localValues: &localValues,
            ids: &ids
        )

        for id in ids {
            // Playlist UUID is baked into content ids. After delete + re-add the
            // catalog has a new prefix, so an unmatched prefix is usually a
            // pending rematch — not a user deletion. Keep the cloud record until
            // a live catalog row claims it. Do not wipe recently watched.
            guard livePrefixes.contains(String(id.prefix(36))) else {
                // No owning playlist/server remains anywhere. Drop orphaned cloud
                // state (favorites/progress keyed to a deleted source). When other
                // sources are still live, keep dead-prefix rows — they may rematch
                // once catalog syncs (delete + re-add with a new playlist UUID).
                if livePrefixes.isEmpty {
                    if let mirror = mirrors[id] {
                        cloudContext.delete(mirror)
                    }
                    shadow.setContentShadow(id, nil)
                }
                continue
            }

            let verdict = CloudSyncMerge.reconcile(
                local: localValues[id]?.values,
                cloud: mirrors[id].map(Self.values(from:)),
                shadow: shadow.contentShadow(id),
                mergeConflict: ContentStateValues.mergeConflict
            )
            try applyContentVerdict(
                verdict,
                id: id,
                mirror: mirrors[id],
                loaded: localValues[id]?.model,
                into: &result
            )
        }
    }

    /// Re-points cloud watch state at catalog rows after a playlist is deleted
    /// and added back (new playlist UUID → new content ids, same provider item).
    private func rematchOrphanedContent(
        mirrors: inout [String: UserContentState],
        localValues: inout [String: LocalContentEntry],
        ids: inout Set<String>
    ) {
        let orphaned = mirrors.filter { localValues[$0.key] == nil }
        guard !orphaned.isEmpty else { return }

        for (oldId, mirror) in orphaned {
            guard let key = ContentIdentity.stableKey(for: oldId),
                  let model = catalogItem(kind: mirror.kind, stableKey: key)
            else { continue }
            let newId = catalogContentId(model)
            guard newId != oldId else { continue }

            if let existing = mirrors[newId], existing !== mirror {
                existing.watchProgress = max(existing.watchProgress, mirror.watchProgress)
                existing.isWatched = existing.isWatched || mirror.isWatched
                existing.lastWatchedDate = laterDate(existing.lastWatchedDate, mirror.lastWatchedDate)
                existing.isFavorite = existing.isFavorite || mirror.isFavorite
                existing.isHidden = existing.isHidden || mirror.isHidden
                if existing.addedToWatchlistDate == nil {
                    existing.addedToWatchlistDate = mirror.addedToWatchlistDate
                }
                cloudContext.delete(mirror)
                mirrors[oldId] = nil
            } else {
                mirror.contentId = newId
                mirrors[newId] = mirror
                mirrors[oldId] = nil
            }

            let preserved = shadow.contentShadow(oldId)
            shadow.setContentShadow(newId, preserved ?? shadow.contentShadow(newId))
            shadow.setContentShadow(oldId, nil)
            ids.remove(oldId)
            ids.insert(newId)
        }
    }

    private func catalogContentId(_ model: any PersistentModel) -> String {
        switch model {
        case let movie as Movie: movie.id
        case let series as Series: series.id
        case let episode as Episode: episode.id
        case let stream as LiveStream: stream.id
        case let category as Category:
            ContentIdentity.categoryCloudId(forCategoryId: category.id) ?? category.id
        default: ""
        }
    }

    private func laterDate(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case let (a?, b?): max(a, b)
        case let (a?, nil): a
        case let (nil, b?): b
        case (nil, nil): nil
        }
    }

    /// Finds the catalog row whose id resolves to `stableKey`, called once per
    /// orphaned mirror.
    ///
    /// Content ids are `"<playlistUUID>-<stableKey>"`. The playlist UUID is
    /// unknown here (that's the whole point of a rematch), so the match can only
    /// be a substring one — and `#Predicate` supports neither `hasSuffix` nor a
    /// regex, so the candidate set can't be narrowed to an exact tail in SQL.
    /// Anchoring the needle with the separator at least drops the "key is a
    /// prefix of another key" hits (`movie-1` no longer matches `10-movie-99`),
    /// and `ContentIdentity.stableKey` still gates the survivors, so a key that
    /// is genuinely another key's tail can't produce a false rematch.
    ///
    /// The memory fix is `propertiesToFetch`: candidates used to be hydrated in
    /// full (plot, artwork paths, every column) across a 20K+ title catalog, per
    /// orphan. Only `id` is ever read from the result — `rematchOrphanedContent`
    /// passes it straight to `catalogContentId` — so faulting just that column
    /// keeps each candidate tiny. Deliberately *not* `fetchLimit`ed: a fuzzy
    /// predicate can place the true match anywhere in the result, so capping it
    /// would silently drop rematches and lose watch state.
    private func catalogItem(kind: SyncedContentKind, stableKey: String) -> (any PersistentModel)? {
        let needle = "-\(stableKey)"
        switch kind {
        case .movie:
            return firstCatalogMatch(
                FetchDescriptor<Movie>(predicate: #Predicate { $0.id.contains(needle) }),
                id: \.id,
                properties: [\.id],
                stableKey: stableKey
            )
        case .series:
            return firstCatalogMatch(
                FetchDescriptor<Series>(predicate: #Predicate { $0.id.contains(needle) }),
                id: \.id,
                properties: [\.id],
                stableKey: stableKey
            )
        case .episode:
            return firstCatalogMatch(
                FetchDescriptor<Episode>(predicate: #Predicate { $0.id.contains(needle) }),
                id: \.id,
                properties: [\.id],
                stableKey: stableKey
            )
        case .live:
            return firstCatalogMatch(
                FetchDescriptor<LiveStream>(predicate: #Predicate { $0.id.contains(needle) }),
                id: \.id,
                properties: [\.id],
                stableKey: stableKey
            )
        case .category:
            guard let localKey = ContentIdentity.categoryLocalStableKey(fromCloudStableKey: stableKey) else {
                return nil
            }
            let localNeedle = "-\(localKey)"
            return firstCatalogMatch(
                FetchDescriptor<Category>(predicate: #Predicate { $0.id.contains(localNeedle) }),
                id: \.id,
                properties: [\.id],
                stableKey: localKey
            )
        }
    }

    private func firstCatalogMatch<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>,
        id: KeyPath<T, String>,
        properties: [PartialKeyPath<T>],
        stableKey: String
    ) -> T? {
        var lightweight = descriptor
        lightweight.propertiesToFetch = properties
        let candidates = (try? catalogContext.fetch(lightweight)) ?? []
        return candidates.first { ContentIdentity.stableKey(for: $0[keyPath: id]) == stableKey }
    }

    // MARK: - Manual EPG sources

    /// Three-way-merges manual EPG sources (those with no owning playlist) with
    /// their cloud mirror, so a custom XMLTV feed added on one device reaches the
    /// others — and a fresh device that's never seen one pulls it in.
    private func reconcileEPGSources(into result: inout CloudSyncReconcileResult) throws {
        let localByID = try fetchLocalManualEPGSources()
        let mirrorsByID = try fetchEPGSourceMirrors()

        var ids = Set(localByID.keys).union(mirrorsByID.keys)
        ids.formUnion(shadow.epgSourceShadowIDs().compactMap(UUID.init(uuidString:)))

        for id in ids {
            let verdict = CloudSyncMerge.reconcile(
                local: localByID[id].map(Self.values(from:)),
                cloud: mirrorsByID[id].map(Self.values(from:)),
                shadow: shadow.epgSourceShadow(id.uuidString),
                mergeConflict: EPGSourceValues.mergeConflict
            )
            applyEPGSourceVerdict(verdict, id: id, local: localByID[id], mirror: mirrorsByID[id], into: &result)
        }
    }

    /// Rebuilds each playlist's derived (linked) EPG source from its current
    /// config, so a playlist pulled in from iCloud gets its guide source on this
    /// device too. Idempotent — only writes when something actually changed.
    private func regenerateLinkedEPGSources() {
        guard let playlists = try? catalogContext.fetch(FetchDescriptor<Playlist>()) else { return }
        for playlist in playlists {
            EPGSourceReconciler.apply(playlist, in: catalogContext)
        }
    }
}

// MARK: - Verdict application

private extension CloudSyncEngine {
    func applyEPGSourceVerdict(
        _ verdict: MergeVerdict<EPGSourceValues>,
        id: UUID,
        local: EPGSource?,
        mirror: SyncedEPGSource?,
        into result: inout CloudSyncReconcileResult
    ) {
        let key = id.uuidString
        switch verdict {
        case .noChange:
            break
        case let .pushToCloud(value):
            applyEPGSourceToCloud(value, id: id, mirror: mirror)
            if value != nil { result.epgSourcesPushed += 1 }
            shadow.setEPGSourceShadow(key, value)
        case let .pullToLocal(value):
            applyEPGSourceToLocal(value, id: id, local: local)
            if value != nil { result.epgSourcesPulled += 1 }
            shadow.setEPGSourceShadow(key, value)
        case let .writeBoth(value):
            applyEPGSourceToCloud(value, id: id, mirror: mirror)
            applyEPGSourceToLocal(value, id: id, local: local)
            result.epgSourcesPushed += 1
            shadow.setEPGSourceShadow(key, value)
        }
    }

    func applyContentVerdict(
        _ verdict: MergeVerdict<ContentStateValues>,
        id: String,
        mirror: UserContentState?,
        loaded: (any PersistentModel)?,
        into result: inout CloudSyncReconcileResult
    ) throws {
        let kind = mirror?.kind ?? Self.kind(of: loaded)
        switch verdict {
        case .noChange:
            break
        case let .pushToCloud(value):
            applyContentToCloud(value, id: id, kind: kind, mirror: mirror)
            if value != nil { result.contentPushed += 1 }
            shadow.setContentShadow(id, value)
        case let .pullToLocal(value):
            // A missing catalog item leaves the change pending (shadow untouched).
            guard try applyContentToLocal(value, id: id, kind: kind, loaded: loaded) else {
                result.contentPending += 1
                return
            }
            if value != nil { result.contentPulled += 1 }
            shadow.setContentShadow(id, value)
        case let .writeBoth(value):
            guard try applyContentToLocal(value, id: id, kind: kind, loaded: loaded) else {
                result.contentPending += 1
                return
            }
            applyContentToCloud(value, id: id, kind: kind, mirror: mirror)
            result.contentPushed += 1
            shadow.setContentShadow(id, value)
        }
    }
}

// MARK: - EPG source mutations

private extension CloudSyncEngine {
    func applyEPGSourceToCloud(_ value: EPGSourceValues?, id: UUID, mirror: SyncedEPGSource?) {
        guard let value else {
            if let mirror { cloudContext.delete(mirror) }
            return
        }
        if let mirror {
            mirror.name = value.name
            mirror.url = value.url
            mirror.isEnabled = value.isEnabled
            mirror.updatedAt = Date()
        } else {
            cloudContext.insert(SyncedEPGSource(id: id, name: value.name, url: value.url, isEnabled: value.isEnabled))
        }
    }

    func applyEPGSourceToLocal(_ value: EPGSourceValues?, id: UUID, local: EPGSource?) {
        guard let value else {
            if let local { catalogContext.delete(local) }
            return
        }
        if let local {
            local.name = value.name
            local.url = value.url
            local.isEnabled = value.isEnabled
        } else {
            let source = EPGSource(name: value.name, url: value.url, playlistID: nil)
            source.id = id
            source.isEnabled = value.isEnabled
            catalogContext.insert(source)
        }
    }
}

// MARK: - Content mutations

/// Not `private`: profile operations in `CloudSyncEngine+Profiles.swift`
/// reuse these helpers (fetch / reset / apply / value extraction).
extension CloudSyncEngine {
    static func kind(of model: (any PersistentModel)?) -> SyncedContentKind? {
        switch model {
        case is Movie: .movie
        case is Series: .series
        case is Episode: .episode
        case is LiveStream: .live
        case is Category: .category
        default: nil
        }
    }

    func applyContentToCloud(_ value: ContentStateValues?, id: String, kind: SyncedContentKind?, mirror: UserContentState?) {
        guard let value, !value.isEmpty else {
            if let mirror { cloudContext.delete(mirror) }
            return
        }
        let kind = kind ?? mirror?.kind ?? .movie
        if let mirror {
            mirror.profileID = activeProfileID // heals a legacy nil record on first touch
            mirror.kindRaw = kind.rawValue
            mirror.watchProgress = value.watchProgress
            mirror.isWatched = value.isWatched
            mirror.lastWatchedDate = value.lastWatchedDate
            mirror.isFavorite = value.isFavorite
            mirror.addedToWatchlistDate = value.addedToWatchlistDate
            mirror.favoriteOrder = value.favoriteOrder
            mirror.isHidden = value.isHidden
            mirror.recommendationVoteRaw = value.recommendationVoteRaw
            mirror.updatedAt = Date()
        } else {
            cloudContext.insert(UserContentState(
                contentId: id,
                kind: kind,
                profileID: activeProfileID,
                watchProgress: value.watchProgress,
                isWatched: value.isWatched,
                lastWatchedDate: value.lastWatchedDate,
                isFavorite: value.isFavorite,
                addedToWatchlistDate: value.addedToWatchlistDate,
                favoriteOrder: value.favoriteOrder,
                isHidden: value.isHidden,
                recommendationVoteRaw: value.recommendationVoteRaw
            ))
        }
    }

    /// Applies a cloud value to the matching local catalog item. Returns false
    /// (without touching the shadow) when the catalog item hasn't synced to this
    /// device yet, so the change stays pending for a later pass.
    func applyContentToLocal(_ value: ContentStateValues?, id: String, kind: SyncedContentKind?, loaded: (any PersistentModel)?) throws -> Bool {
        guard let kind else { return true } // nothing to apply (shadow-only id)
        let values = value ?? ContentStateValues(watchProgress: 0, isWatched: false, lastWatchedDate: nil, isFavorite: false, addedToWatchlistDate: nil, favoriteOrder: nil, isHidden: false)

        switch kind {
        case .movie:
            guard let movie = try (loaded as? Movie) ?? fetchMovie(id) else { return false }
            movie.watchProgress = values.watchProgress
            movie.isWatched = values.isWatched
            movie.lastWatchedDate = values.lastWatchedDate
            movie.isFavorite = values.isFavorite
            movie.addedToWatchlistDate = values.addedToWatchlistDate
            movie.recommendationVoteRaw = values.recommendationVoteRaw
        case .series:
            guard let series = try (loaded as? Series) ?? fetchSeries(id) else { return false }
            series.isFavorite = values.isFavorite
            series.addedToWatchlistDate = values.addedToWatchlistDate
            series.lastWatchedDate = values.lastWatchedDate
            series.recommendationVoteRaw = values.recommendationVoteRaw
        case .episode:
            guard let episode = try (loaded as? Episode) ?? fetchEpisode(id) else { return false }
            episode.watchProgress = values.watchProgress
            episode.isWatched = values.isWatched
            episode.lastWatchedDate = values.lastWatchedDate
        case .live:
            guard let stream = try (loaded as? LiveStream) ?? fetchLiveStream(id) else { return false }
            stream.isFavorite = values.isFavorite
            stream.favoriteOrder = values.favoriteOrder
            stream.lastWatchedDate = values.lastWatchedDate
            stream.isHidden = values.isHidden
        case .category:
            let localId = ContentIdentity.categoryId(fromCloudContentId: id) ?? id
            guard let category = try (loaded as? Category) ?? fetchCategory(localId) else { return false }
            category.isHidden = values.isHidden
        }
        return true
    }

    /// Resets an orphaned local item's user state to defaults so it stops
    /// regenerating cloud records after its playlist was deleted.
    func resetLocalContent(_ entry: LocalContentEntry) {
        switch entry.model {
        case let movie as Movie:
            movie.watchProgress = 0
            movie.isWatched = false
            movie.lastWatchedDate = nil
            movie.isFavorite = false
            movie.addedToWatchlistDate = nil
            movie.recommendationVoteRaw = 0
        case let series as Series:
            series.isFavorite = false
            series.addedToWatchlistDate = nil
            series.lastWatchedDate = nil
            series.recommendationVoteRaw = 0
        case let episode as Episode:
            episode.watchProgress = 0
            episode.isWatched = false
            episode.lastWatchedDate = nil
        case let stream as LiveStream:
            stream.isFavorite = false
            stream.favoriteOrder = nil
            stream.isHidden = false
        case let category as Category:
            category.isHidden = false
        default:
            break
        }
    }
}
