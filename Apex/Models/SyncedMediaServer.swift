import Foundation
import SwiftData

/// CloudKit-synced mirror of a `MediaServer` connection.
///
/// The synced media catalog (`Movie` / `Series` / `Episode` rows) stays local —
/// it is large and re-derivable from the server, like IPTV catalogs. This record
/// carries only what a fresh device needs to reconnect and run `MediaServerSyncService`.
///
/// `id` matches `MediaServer.id` verbatim so per-content user state keyed by
/// `{serverUUID}-movie-…` ids reconciles without a lookup table.
@Model
final class SyncedMediaServer {
    var id: UUID = UUID()
    var name: String = ""
    var baseURL: String = ""
    var kindRaw: String = MediaServerKind.jellyfin.rawValue

    @Attribute(.allowsCloudEncryption) var username: String = ""
    @Attribute(.allowsCloudEncryption) var password: String = ""

    @Attribute(.allowsCloudEncryption) var accessToken: String?
    @Attribute(.allowsCloudEncryption) var plexToken: String?

    var userId: String?
    var plexServerIdentifier: String?
    var syncEnabled: Bool = true
    var sortOrder: Int = 0
    var updatedAt: Date = Date()
    /// Set when the user deletes this connection. Kept as a CloudKit row so
    /// other devices apply the removal instead of treating a missing record as
    /// "import hasn't arrived yet" and re-publishing the server.
    var deletedAt: Date?

    init(
        id: UUID,
        name: String,
        baseURL: String,
        kindRaw: String,
        username: String,
        password: String,
        accessToken: String?,
        plexToken: String?,
        userId: String?,
        plexServerIdentifier: String?,
        syncEnabled: Bool,
        sortOrder: Int,
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.kindRaw = kindRaw
        self.username = username
        self.password = password
        self.accessToken = accessToken
        self.plexToken = plexToken
        self.userId = userId
        self.plexServerIdentifier = plexServerIdentifier
        self.syncEnabled = syncEnabled
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
