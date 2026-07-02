//
//  ChannelLogoLoader.swift
//  Apex
//
//  Channel logos are small (often <200 px) grayscale PNGs. The poster pipeline
//  behind `CachedAsyncImage` downsampled them through ImageIO thumbnails, which
//  breaks many IPTV logos even though the bytes are fine — every other IPTV app
//  simply does `UIImage(data:)` and it works. This loader mirrors that path.
//

import Foundation

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

enum ChannelLogoLoader {
    private static let memory = LogoMemoryCache.shared

    private static let session: URLSession = ProviderURLSession.make(
        timeout: 30,
        resourceTimeout: 60,
        maxConnectionsPerHost: 4,
        urlCache: nil,
        cachePolicy: .reloadIgnoringLocalCacheData
    )

    /// Synchronous peek: memory, then disk. Used so category lists can paint
    /// logos on the first frame instead of waiting on a `.task` that List cancels.
    nonisolated static func cachedImage(for url: URL) -> PlatformImage? {
        let key = url.absoluteString
        if let cached = memory.image(for: key) { return cached }
        guard let data = ImageDiskCache.shared.data(for: key),
              let image = PlatformImage(data: data) else { return nil }
        memory.insert(image, for: key)
        return image
    }

    /// Warms memory/disk for a batch of channel rows (category lists).
    static func prefetch(_ urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                guard cachedImage(for: url) == nil else { continue }
                group.addTask {
                    _ = try? await image(for: url)
                }
            }
        }
    }

    /// Disk cache → network → `PlatformImage(data:)`. No downsampling.
    static func image(for url: URL) async throws -> PlatformImage {
        let key = url.absoluteString
        if let cached = cachedImage(for: url) { return cached }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            throw ImagePipelineError.httpStatus(http.statusCode)
        }

        ImageDiskCache.shared.store(data, for: key)
        guard let image = PlatformImage(data: data) else {
            throw ImagePipelineError.decodingFailed
        }
        memory.insert(image, for: key)
        return image
    }
}

// MARK: - Memory cache

/// Decoded channel logos only — keyed by URL, separate from the poster pipeline's
/// size-dependent memory cache.
private final class LogoMemoryCache: @unchecked Sendable {
    static let shared = LogoMemoryCache()

    private let cache = NSCache<NSString, PlatformImage>()

    private init() {
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func image(for key: String) -> PlatformImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: PlatformImage, for key: String) {
        #if canImport(UIKit)
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale) * 4
        #else
            let cost = Int(image.size.width * image.size.height) * 4
        #endif
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}
