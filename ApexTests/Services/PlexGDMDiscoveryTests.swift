//
//  PlexGDMDiscoveryTests.swift
//  ApexTests
//

import Foundation
@testable import Apex
import Testing

struct PlexGDMDiscoveryTests {
    @Test func parseGDMResponse() {
        let payload = """
        HTTP/1.0 200 OK
        Content-Type: plex/media-server
        Name: Living Room Plex
        Port: 32400
        Resource-Identifier: abc123def456
        """.data(using: .utf8)!

        let server = PlexGDMDiscovery.parseResponse(payload, fromHost: "192.168.1.50")
        #expect(server?.name == "Living Room Plex")
        #expect(server?.port == 32400)
        #expect(server?.resourceIdentifier == "abc123def456")
        #expect(server?.host == "192.168.1.50")
        #expect(server?.baseURL?.absoluteString == "http://192.168.1.50:32400")
    }
}
