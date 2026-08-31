//
//  PlexGDMDiscovery.swift
//  Apex
//
//  Plex GDM ("G'Day Mate") local server discovery — the same UDP multicast
//  protocol the official Plex apps use. Finds servers on the LAN by real IP
//  (e.g. http://192.168.1.50:32400) even when plex.tv only advertises broken
//  Docker `.plex.direct` URLs.
//

import Darwin
import Foundation
import OSLog

nonisolated struct PlexGDMServer: Sendable, Equatable {
    let resourceIdentifier: String
    let name: String
    let host: String
    let port: Int

    var baseURL: URL? {
        URL(string: "http://\(host):\(port)")
    }
}

nonisolated enum PlexGDMDiscovery {
    private static let multicastAddress = "239.0.0.250"
    private static let discoveryPort: UInt16 = 32414
    private static let searchMessage = "M-SEARCH * HTTP/1.0\r\n\r\n"

    /// Broadcasts a GDM M-SEARCH and collects Plex Media Server responses.
    static func discover(timeout: TimeInterval = 2.0) async -> [PlexGDMServer] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: scan(timeout: timeout))
            }
        }
    }

    private static func scan(timeout: TimeInterval) -> [PlexGDMServer] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var bindAddr = sockaddr_in()
        bindAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_port = 0
        bindAddr.sin_addr.s_addr = in_addr_t(INADDR_ANY)
        let bindOK = withUnsafePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindOK == 0 else { return [] }

        var mreq = ip_mreq()
        _ = inet_pton(AF_INET, multicastAddress, &mreq.imr_multiaddr)
        mreq.imr_interface.s_addr = INADDR_ANY
        _ = setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, socklen_t(MemoryLayout<ip_mreq>.size))

        var ttl: UInt8 = 1
        _ = setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))

        var broadcast: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))

        var tv = timeval(tv_sec: 0, tv_usec: 300_000)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        sendSearch(fd: fd, host: multicastAddress, port: discoveryPort)
        // Subnet broadcast fallback — some Docker/NAS installs respond here but not multicast.
        sendSearch(fd: fd, host: "255.255.255.255", port: discoveryPort)

        var results: [PlexGDMServer] = []
        var seen = Set<String>()
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            var addr = sockaddr_in()
            var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            var buffer = [UInt8](repeating: 0, count: 4096)
            let received = withUnsafeMutablePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(fd, &buffer, buffer.count, 0, sa, &addrLen)
                }
            }
            guard received > 0 else { continue }

            let host = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                    String(cString: inet_ntoa(sin.pointee.sin_addr))
                }
            }
            let data = Data(buffer.prefix(received))
            guard let server = parseResponse(data, fromHost: host) else { continue }
            let key = "\(server.resourceIdentifier)|\(server.host)|\(server.port)"
            guard seen.insert(key).inserted else { continue }
            results.append(server)
            Logger.network.info("Plex GDM found \(server.name, privacy: .public) at \(server.host, privacy: .public):\(server.port)")
        }

        return results
    }

    private static func sendSearch(fd: Int32, host: String, port: UInt16) {
        var dest = sockaddr_in()
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = port.bigEndian
        _ = inet_pton(AF_INET, host, &dest.sin_addr)
        searchMessage.withCString { ptr in
            _ = withUnsafePointer(to: &dest) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, ptr, strlen(ptr), 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    static func parseResponse(_ data: Data, fromHost: String) -> PlexGDMServer? {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii) else { return nil }
        guard text.contains("200 OK") || text.contains("plex/media-server") else { return nil }
        guard let resourceID = parseField("Resource-Identifier", in: text),
              let name = parseField("Name", in: text) else { return nil }
        let port = parseField("Port", in: text).flatMap(Int.init) ?? 32400
        return PlexGDMServer(resourceIdentifier: resourceID, name: name, host: fromHost, port: port)
    }

    private static func parseField(_ key: String, in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key):") else { continue }
            let value = trimmed.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
