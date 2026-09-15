//
//  EPGSyncTests.swift
//  ApexTests
//
//  EPG import: single-pass XMLTV, channel-id/name matching, and per-channel caps.
//

@testable import Apex
import Foundation
import SwiftData
import Testing

struct EPGSyncTests {
    @Test func `on-demand guide survives reopening its disk store`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Apex-EPG-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("catalog.store")
        let schema = Schema([EPGListing.self])
        let configuration = ModelConfiguration(
            "EPGPersistence",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let start = Date().addingTimeInterval(-60)
        let end = Date().addingTimeInterval(3_600)

        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            let inserted = await EPGAPISync.persist(
                programsByChannel: [
                    "news.1": [EPGProgram(title: "News", description: "", start: start, end: end)]
                ],
                container: container
            )
            #expect(inserted == 1)
        }

        let reopened = try ModelContainer(for: schema, configurations: configuration)
        let listings = try ModelContext(reopened).fetch(FetchDescriptor<EPGListing>())
        #expect(listings.count == 1)
        #expect(listings.first?.title == "News")
    }

    @Test @MainActor func `section cache evicts old sections but keeps recent data`() {
        let cache = LiveTVSectionEPGCache()
        let now = Date()
        let program = EPGProgram(title: "News", description: "", start: now, end: now.addingTimeInterval(3600))
        for index in 0 ..< 20 {
            let token = "section-\(index)"
            cache.activate(section: token)
            cache.merge(section: token, loaded: ([:], ["channel": [program]]))
        }
        cache.activate(section: "section-18")
        #expect(cache.programsByChannel["channel"] == [program])
        cache.activate(section: "section-0")
        #expect(cache.programsByChannel.isEmpty)
    }

    @Test @MainActor func `expired section data needs loading again`() {
        let cache = LiveTVSectionEPGCache()
        let stream = LiveStream(id: "test-live-1", streamId: 1, name: "News")
        let now = Date()
        let expired = EPGProgram(title: "Old", description: "", start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600))
        cache.activate(section: "news")
        cache.merge(section: "news", loaded: ([:], [stream.primaryEPGChannelId: [expired]]))
        #expect(cache.channelsNeedingLoad([stream]).count == 1)
        let current = EPGProgram(title: "Current", description: "", start: now.addingTimeInterval(-60), end: now.addingTimeInterval(3600))
        cache.merge(section: "news", loaded: ([:], [stream.primaryEPGChannelId: [current]]))
        #expect(cache.channelsNeedingLoad([stream]).isEmpty)
    }

    private func writeTempFile(_ content: String, ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "." + ext)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func xmltvTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Offset-less wall clock — interpreted in the device/server zone by `parseEPG`.
        return formatter.string(from: date)
    }

    @Test func `xmltv display name links programmes when ids differ`() async throws {
        let start = Date().addingTimeInterval(3600)
        let end = start.addingTimeInterval(3600)
        let startStamp = Self.xmltvTimestamp(start)
        let endStamp = Self.xmltvTimestamp(end)
        let xmltv = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <channel id="provider-xml-id-99">
            <display-name>CNN HD</display-name>
          </channel>
          <programme start="\(startStamp)" stop="\(endStamp)" channel="provider-xml-id-99">
            <title>Breaking News</title>
          </programme>
        </tv>
        """
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let playlistID = UUID()
        context.insert(
            LiveStream(
                id: "\(playlistID.uuidString)-live-42",
                streamId: 42,
                name: "CNN HD",
                epgChannelId: nil
            )
        )
        try context.save()

        let epgFile = try writeTempFile(xmltv, ext: "xml")
        defer { try? FileManager.default.removeItem(at: epgFile) }

        let source = EPGSource(name: "Test", url: epgFile.absoluteString, playlistID: playlistID)
        context.insert(source)
        try context.save()

        let didSync = await EPGSyncManager(modelContainer: container).syncAllSources()
        #expect(didSync)

        let listings = try ModelContext(container).fetch(FetchDescriptor<EPGListing>())
        #expect(listings.count == 1)
        #expect(listings.first?.title == "Breaking News")
        #expect(listings.first?.channelId == "42")
    }

    @Test func `stream id matches xmltv channel when epg channel id is nil`() async throws {
        let start = Date().addingTimeInterval(3600)
        let end = start.addingTimeInterval(3600)
        let xmltv = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <programme start="\(Self.xmltvTimestamp(start))" stop="\(Self.xmltvTimestamp(end))" channel="42">
            <title>Breaking News</title>
          </programme>
        </tv>
        """
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let playlistID = UUID()
        context.insert(
            LiveStream(
                id: "\(playlistID.uuidString)-live-42",
                streamId: 42,
                name: "CNN HD",
                epgChannelId: nil
            )
        )
        try context.save()

        let epgFile = try writeTempFile(xmltv, ext: "xml")
        defer { try? FileManager.default.removeItem(at: epgFile) }

        context.insert(EPGSource(name: "Test", url: epgFile.absoluteString, playlistID: playlistID))
        try context.save()

        let didSync = await EPGSyncManager(modelContainer: container).syncAllSources()
        #expect(didSync)
        let listings = try ModelContext(container).fetch(FetchDescriptor<EPGListing>())
        #expect(listings.count == 1)
    }

    @Test func `numeric epg channel id matches zero padded xmltv id`() async throws {
        let start = Date().addingTimeInterval(3600)
        let end = start.addingTimeInterval(3600)
        let startStamp = Self.xmltvTimestamp(start)
        let endStamp = Self.xmltvTimestamp(end)
        let xmltv = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <programme start="\(startStamp)" stop="\(endStamp)" channel="08821">
            <title>Sports Desk</title>
          </programme>
        </tv>
        """
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let playlistID = UUID()
        context.insert(
            LiveStream(
                id: "\(playlistID.uuidString)-live-1",
                streamId: 1,
                name: "Sports",
                epgChannelId: "8821"
            )
        )
        try context.save()

        let epgFile = try writeTempFile(xmltv, ext: "xml")
        defer { try? FileManager.default.removeItem(at: epgFile) }

        context.insert(EPGSource(name: "Test", url: epgFile.absoluteString, playlistID: playlistID))
        try context.save()

        let didSync = await EPGSyncManager(modelContainer: container).syncAllSources()
        #expect(didSync)
        let listings = try ModelContext(container).fetch(FetchDescriptor<EPGListing>())
        #expect(listings.count == 1)
        #expect(listings.first?.title == "Sports Desk")
    }

    @Test func `import skips programmes that already ended`() async throws {
        let airingStart = Date().addingTimeInterval(3600)
        let airingEnd = airingStart.addingTimeInterval(3600)
        let expiredEnd = Date().addingTimeInterval(-7200)
        let expiredStart = expiredEnd.addingTimeInterval(-3600)
        let xmltv = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <programme start="\(Self.xmltvTimestamp(airingStart))" stop="\(Self.xmltvTimestamp(airingEnd))" channel="news.1">
            <title>On Soon</title>
          </programme>
          <programme start="\(Self.xmltvTimestamp(expiredStart))" stop="\(Self.xmltvTimestamp(expiredEnd))" channel="news.1">
            <title>Already Aired</title>
          </programme>
        </tv>
        """
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let playlistID = UUID()
        context.insert(
            LiveStream(
                id: "\(playlistID.uuidString)-live-1",
                streamId: 1,
                name: "News",
                epgChannelId: "news.1"
            )
        )
        try context.save()

        let epgFile = try writeTempFile(xmltv, ext: "xml")
        defer { try? FileManager.default.removeItem(at: epgFile) }

        context.insert(EPGSource(name: "Test", url: epgFile.absoluteString, playlistID: playlistID))
        try context.save()

        let didSync = await EPGSyncManager(modelContainer: container).syncAllSources()
        #expect(didSync)
        let listings = try ModelContext(container).fetch(FetchDescriptor<EPGListing>())
        #expect(listings.count == 1)
        #expect(listings.contains { $0.title == "On Soon" })
        #expect(!listings.contains { $0.title == "Already Aired" })
    }

    @Test func `per channel insert cap prevents guide table explosion`() async throws {
        let start = Date().addingTimeInterval(7200)
        var programmes = ""
        let slotCount = EPGRetention.maxListingsPerChannel + 4
        for index in 0 ..< slotCount {
            let slotStart = start.addingTimeInterval(Double(index) * 1800)
            let slotEnd = slotStart.addingTimeInterval(1800)
            programmes += """
              <programme start="\(Self.xmltvTimestamp(slotStart))" stop="\(Self.xmltvTimestamp(slotEnd))" channel="news.1">
                <title>Slot \(index)</title>
              </programme>
            """
        }
        let xmltv = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
        \(programmes)
        </tv>
        """
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let playlistID = UUID()
        context.insert(
            LiveStream(
                id: "\(playlistID.uuidString)-live-1",
                streamId: 1,
                name: "News",
                epgChannelId: "news.1"
            )
        )
        try context.save()

        let epgFile = try writeTempFile(xmltv, ext: "xml")
        defer { try? FileManager.default.removeItem(at: epgFile) }

        context.insert(EPGSource(name: "Test", url: epgFile.absoluteString, playlistID: playlistID))
        try context.save()

        let didSync = await EPGSyncManager(modelContainer: container).syncAllSources()
        #expect(didSync)
        let verify = ModelContext(container)
        let listings = try verify.fetch(FetchDescriptor<EPGListing>())
        #expect(!listings.isEmpty)
        #expect(listings.count <= EPGRetention.maxListingsPerChannel)
    }

    @Test func `stale xmltv cache is not set when xmltv matches zero channels`() async throws {
        let expiredEnd = Date().addingTimeInterval(-7200)
        let expiredStart = expiredEnd.addingTimeInterval(-3600)
        let xmltv = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <programme start="\(Self.xmltvTimestamp(expiredStart))" stop="\(Self.xmltvTimestamp(expiredEnd))" channel="unknown.99">
            <title>Expired On Other Id</title>
          </programme>
        </tv>
        """
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let playlist = Playlist(
            name: "Provider A",
            serverURL: "http://example.com",
            username: "u",
            password: "p"
        )
        context.insert(playlist)
        let playlistID = playlist.id
        context.insert(
            LiveStream(
                id: "\(playlistID.uuidString)-live-1",
                streamId: 1,
                name: "News",
                epgChannelId: "news.1"
            )
        )
        try context.save()

        let epgFile = try writeTempFile(xmltv, ext: "xml")
        defer { try? FileManager.default.removeItem(at: epgFile) }

        context.insert(EPGSource(name: "Test", url: epgFile.absoluteString, playlistID: playlistID))
        try context.save()

        EPGStaleXMLTVCache.clearXMLTVBulkStale(playlistID: playlistID)
        _ = await EPGSyncManager(modelContainer: container).syncAllSources()
        #expect(EPGStaleXMLTVCache.shouldSkipXMLTVDownload(playlistID: playlistID) == false)
    }

    @Test func `stale xmltv cache is set only when matched programmes are uniformly expired`() {
        let playlistID = UUID()
        EPGStaleXMLTVCache.clearXMLTVBulkStale(playlistID: playlistID)
        EPGStaleXMLTVCache.markXMLTVBulkStale(playlistID: playlistID)
        #expect(EPGStaleXMLTVCache.shouldSkipXMLTVDownload(playlistID: playlistID))
        EPGStaleXMLTVCache.clearXMLTVBulkStale(playlistID: playlistID)
        #expect(!EPGStaleXMLTVCache.shouldSkipXMLTVDownload(playlistID: playlistID))
    }

    @Test func `external epg single pass matches display names`() throws {
        let start = Date().addingTimeInterval(3600)
        let end = start.addingTimeInterval(3600)
        let startStamp = Self.xmltvTimestamp(start)
        let endStamp = Self.xmltvTimestamp(end)
        let xmltv = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <channel id="hbo.us">
            <display-name>HBO HD</display-name>
          </channel>
          <programme start="\(startStamp)" stop="\(endStamp)" channel="hbo.us">
            <title>Westworld</title>
            <desc>Season finale</desc>
          </programme>
        </tv>
        """
        let epgFile = try writeTempFile(xmltv, ext: "xml")
        defer { try? FileManager.default.removeItem(at: epgFile) }

        struct TestIdentity: EPGChannelIdentity {
            let streamId: Int
            let name: String
            let epgChannelId: String?
            let customSid: String?
        }

        let identities = [
            TestIdentity(streamId: 7, name: "HBO HD", epgChannelId: "hbo.us", customSid: nil)
        ]

        var batches: [[ParsedProgramme]] = []
        let stats = XMLTVParser.importExternalEPG(
            fileURL: epgFile,
            identities: identities,
            batchSize: 10
        ) { _, _, batch in
            batches.append(batch)
        }

        #expect(stats.matchedProgrammes == 1)
        #expect(!stats.catalog.isEmpty)
        #expect(batches.flatMap(\.self).first?.title == "Westworld")
    }
}
