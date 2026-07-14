//
//  ProviderURLSession.swift
//  Apex
//
//  Shared URLSession factory for IPTV provider hosts. Many panels run on shared
//  hosting where the TLS certificate belongs to the host (e.g. *.anonym0us.xyz)
//  rather than the provider's custom domain. The Simulator is lenient; a real
//  device rejects the hostname mismatch at the TLS layer regardless of ATS.
//
//  Scoped to provider traffic only — TMDB, OMDb, Trakt and other services keep
//  their own sessions with standard certificate validation.
//

import Foundation

/// Accepts any server certificate for provider API, playlist, icon and stream URLs.
final class ProviderURLSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    static let shared = ProviderURLSessionDelegate()

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

enum ProviderURLSession {
    /// Builds a session that tolerates mismatched provider TLS certificates.
    /// Cache is disabled so stale error responses (401/403 from provider outages)
    /// never block playback after the provider recovers.
    static func make(
        timeout: TimeInterval = 30,
        resourceTimeout: TimeInterval = 120,
        maxConnectionsPerHost: Int = 1,
        additionalHeaders: [String: String] = [:],
        urlCache: URLCache? = nil,
        cachePolicy: URLRequest.CachePolicy? = nil
    ) -> URLSession {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = maxConnectionsPerHost
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = resourceTimeout
        // Disable URL caching for provider traffic. IPTV streams and API calls
        // should never be served from cache — a stale 401/403 cached during a
        // provider outage would block playback even after the provider recovers.
        config.urlCache = urlCache ?? nil
        config.requestCachePolicy = cachePolicy ?? .reloadIgnoringLocalCacheData
        if !additionalHeaders.isEmpty {
            config.httpAdditionalHeaders = additionalHeaders
        }
        return URLSession(configuration: config, delegate: ProviderURLSessionDelegate.shared, delegateQueue: nil)
    }
}
