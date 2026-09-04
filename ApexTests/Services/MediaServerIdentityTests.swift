import Foundation
@testable import Apex
import Testing

struct MediaServerIdentityTests {
    @Test func `IPTV catalog ids parse as UUID-movie but are not media-server items`() {
        let playlistID = UUID()
        let movieID = "\(playlistID.uuidString)-movie-42"
        #expect(MediaServerIdentity.parseCatalogID(movieID) != nil)

        let categoryID = "\(playlistID.uuidString)-vod-5"
        #expect(MediaServerIdentity.isMediaServerCategoryID(categoryID) == false)
    }

    @Test func `media-server library category ids are recognized`() {
        let serverID = UUID()
        let categoryID = MediaServerIdentity.libraryCategoryID(serverUUID: serverID, libraryID: "1")
        #expect(MediaServerIdentity.isMediaServerCategoryID(categoryID))
        #expect(categoryID.hasPrefix("\(serverID.uuidString)-library-"))
    }

    @Test func `M3U group names containing library do not count as media-server categories`() {
        let playlistID = UUID()
        let categoryID = "\(playlistID.uuidString)-vod-Kids-library-3"
        #expect(MediaServerIdentity.isMediaServerCategoryID(categoryID) == false)
    }

    @Test func `belongsToKnownMediaServer requires a configured server UUID`() {
        let serverID = UUID()
        let playlistID = UUID()
        let plexMovie = MediaServerIdentity.movieID(serverUUID: serverID, remoteID: "99")
        let iptvMovie = "\(playlistID.uuidString)-movie-99"
        let known = Set([serverID.uuidString])
        #expect(MediaServerIdentity.belongsToKnownMediaServer(plexMovie, serverIDs: known))
        #expect(MediaServerIdentity.belongsToKnownMediaServer(iptvMovie, serverIDs: known) == false)
    }
}
