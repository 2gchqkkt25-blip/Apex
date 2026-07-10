//
//  CachedAsyncImage.swift
//  Apex
//
//  A drop-in replacement for SwiftUI's `AsyncImage` that fixes the reliability
//  problems that make posters and backdrops fail to load:
//
//  • Memory + disk caching (see `ImagePipeline`), so images survive cell reuse
//    and app launches instead of re-downloading and flashing placeholders.
//  • Automatic retry on transient network failures.
//  • Optional downsampling via `maxPixelSize` (longest edge in points; converted
//    to pixels using the display scale) to cut memory and decode time for cards.
//    Pass `nil` for full-resolution artwork such as tvOS 4K heroes.
//
//  The closure API mirrors `AsyncImage` — it hands back an `AsyncImagePhase`
//  (`.empty` / `.success` / `.failure`) — so migrating a call site is usually
//  just renaming `AsyncImage` to `CachedAsyncImage`.
//

import OSLog
import SwiftUI

struct CachedAsyncImage<Content: View>: View {
    private let url: URL?
    /// Longest edge to decode to, in points. `nil` keeps full resolution.
    private let maxPixelSize: CGFloat?
    private let transaction: Transaction
    private let content: (AsyncImagePhase) -> Content

    @Environment(\.displayScale) private var displayScale

    init(
        url: URL?,
        maxPixelSize: CGFloat? = nil,
        transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.transaction = transaction
        self.content = content
    }

    var body: some View {
        // `.id(taskID)` on an inner loader resets `@State` when a `LazyVStack`
        // cell is recycled for a different URL — without this, a prior channel's
        // `.success` phase can stick around and render blank/wrong artwork.
        CachedAsyncImageLoader(
            url: url,
            pixelSize: pixelSize,
            taskID: taskID,
            transaction: transaction,
            content: content
        )
        .id(taskID)
    }

    /// Restart the load whenever the URL or target size changes (e.g. cell reuse).
    private var taskID: String {
        guard let url else { return "nil" }
        return ImagePipeline.memoryKey(url, maxPixelSize: pixelSize)
    }

    /// Target size in pixels, or `nil` for full resolution.
    private var pixelSize: CGFloat? {
        guard let maxPixelSize else { return nil }
        return maxPixelSize * displayScale
    }
}

// MARK: - Loader

/// Holds load state. Wrapped by `CachedAsyncImage` with `.id(taskID)` so
/// `@State` resets on cell reuse in lazy containers.
private struct CachedAsyncImageLoader<Content: View>: View {
    let url: URL?
    let pixelSize: CGFloat?
    let taskID: String
    let transaction: Transaction
    let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    var body: some View {
        content(url == nil ? .failure(URLError(.badURL)) : phase)
            .task(id: taskID) { await load() }
    }

    private func load() async {
        guard let url else {
            phase = .failure(URLError(.badURL))
            Logger.network.warning("[ImageDebug] CachedAsyncImage: nil URL — showing failure")
            return
        }

        // Synchronous cache hit: render immediately, no placeholder flash.
        if let cached = ImagePipeline.cachedImage(for: url, maxPixelSize: pixelSize) {
            phase = .success(Image(platformImage: cached).renderingMode(.original))
            return
        }

        // Only show the empty/loading state if we have never successfully loaded
        // this image before in this view's lifetime. When a `@Query` re-evaluation
        // recreates us and the memory cache was evicted (e.g. after a brief
        // background), keep showing the previous phase (which is `.empty` for a
        // truly new load, or `.success` if `.id(taskID)` matched — though `.id`
        // reset means we'd start fresh anyway). The key insight: don't set
        // `.empty` here if we already have a success — let the disk load finish
        // without flashing a spinner.
        if case .success = phase {
            // Already showing an image from a previous load — keep it visible while
            // we confirm or refresh from disk/network below.
        } else {
            phase = .empty
        }

        do {
            let image = try await ImagePipeline.shared.image(for: url, maxPixelSize: pixelSize)
            withTransaction(transaction) {
                phase = .success(Image(platformImage: image).renderingMode(.original))
            }
        } catch is CancellationError {
            // View went away mid-load; the detached fetch still warms the cache.
        } catch {
            Logger.network.warning("[ImageDebug] CachedAsyncImage load failed: \(url.absoluteString) — \(error.localizedDescription)")
            withTransaction(transaction) {
                phase = .failure(error)
            }
        }
    }
}
