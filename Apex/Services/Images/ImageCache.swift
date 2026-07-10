//
//  ImageCache.swift
//  Apex
//
//  Two-tier image caching that backs `CachedAsyncImage`:
//
//  • `ImageMemoryCache` keeps *decoded* (and optionally downsampled) images in
//    an `NSCache`, keyed by URL + target size. This is what makes scrolling
//    smooth — once an image is decoded it survives cell reuse, so a poster that
//    scrolls off and back never re-decodes or flashes a placeholder.
//  • `ImageDiskCache` persists the *original* downloaded bytes on disk, keyed by
//    URL only. It survives app launches and, crucially, works regardless of
//    whether the (often flaky IPTV) image host sends sensible cache headers —
//    which `URLCache` alone does not guarantee.
//
//  Decoding/downsampling lives here too so the pipeline can offload it.
//

import CryptoKit
import Foundation
import ImageIO
import OSLog
import SwiftUI

#if canImport(UIKit)
    import UIKit

    typealias PlatformImage = UIImage
#elseif canImport(AppKit)
    import AppKit

    typealias PlatformImage = NSImage
#endif

extension Image {
    /// Bridges a decoded platform image into a SwiftUI `Image` on either UIKit
    /// (iOS/tvOS/visionOS) or AppKit (macOS).
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
            self.init(uiImage: platformImage)
        #else
            self.init(nsImage: platformImage)
        #endif
    }
}

// MARK: - Memory cache

/// Thread-safe in-memory store of decoded images. `NSCache` evicts under memory
/// pressure on its own, so we only set a generous cost ceiling.
final nonisolated class ImageMemoryCache: @unchecked Sendable {
    static let shared = ImageMemoryCache()

    private let cache = NSCache<NSString, PlatformImage>()

    private init() {
        // NSCache also purges on memory warnings, but the ceiling matters: a
        // decoded-image cache sized for the whole process is a prime jetsam
        // target. Apple TV has a far tighter per-app memory budget than
        // iPhone/iPad, so keep its ceiling small and lean on the disk cache for
        // cheap re-decodes. iOS/iPadOS/macOS keep the generous ceiling for
        // smooth poster scrolling.
        #if os(tvOS)
            cache.totalCostLimit = 64 * 1024 * 1024
        #else
            cache.totalCostLimit = 256 * 1024 * 1024
        #endif
        #if canImport(UIKit)
            // NSCache evicts under pressure on its own, but silently and only
            // reactively. Observe the explicit warning too so we drop *all* decoded
            // pixels at once and leave a breadcrumb — a suspended app holding 256 MB
            // of posters is a prime jetsam target, which reads to users as the app
            // being slow / reloading after a long time in the background. The disk
            // cache still holds the bytes, so this forces a re-decode, not a
            // re-download. The singleton lives for the whole process, so the observer
            // never needs removing.
            NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.purge(reason: "memory warning")
            }
        #endif
    }

    func image(for key: String) -> PlatformImage? {
        guard let image = cache.object(forKey: key as NSString) else { return nil }
        #if canImport(UIKit)
            if image.size.width <= 0 || image.size.height <= 0 { return nil }
            if image.cgImage?.colorSpace?.model == .monochrome { return nil }
        #elseif canImport(AppKit)
            if image.size.width <= 0 || image.size.height <= 0 { return nil }
            if image.cgImage(forProposedRect: nil, context: nil, hints: nil)?
                .colorSpace?.model == .monochrome { return nil }
            image.isTemplate = false
        #endif
        return image
    }

    func insert(_ image: PlatformImage, for key: String) {
        #if canImport(UIKit)
            if image.size.width <= 0 || image.size.height <= 0 { return }
            if image.cgImage?.colorSpace?.model == .monochrome { return }
        #elseif canImport(AppKit)
            if image.size.width <= 0 || image.size.height <= 0 { return }
            if image.cgImage(forProposedRect: nil, context: nil, hints: nil)?
                .colorSpace?.model == .monochrome { return }
            image.isTemplate = false
        #endif
        cache.setObject(image, forKey: key as NSString, cost: image.approximateByteCost)
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    /// Drops every decoded image and logs why. Called on memory warnings and when
    /// the app backgrounds, to shrink the resident footprint a suspended app keeps.
    /// The disk cache still holds the original bytes, so this only forces a re-decode.
    func purge(reason: String) {
        cache.removeAllObjects()
        Logger.memory.notice("Image memory cache purged (\(reason, privacy: .public))")
    }

    // MARK: - Deferred purge

    /// A background purge fires after a delay so brief app switches (e.g.
    /// checking a notification, switching to Messages for 3 seconds) don't wipe
    /// the image cache and flash spinners on every cover when the user returns.
    private var deferredPurgeWork: DispatchWorkItem?
    private static let deferredPurgeDelay: TimeInterval = 8

    /// Schedules a cache purge after a delay. If the user returns to the app
    /// before the delay fires, `cancelDeferredPurge()` prevents it.
    func scheduleDeferredPurge() {
        cancelDeferredPurge()
        let work = DispatchWorkItem { [weak self] in
            self?.purge(reason: "app backgrounded (extended)")
        }
        deferredPurgeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.deferredPurgeDelay, execute: work)
    }

    /// Cancels a pending deferred purge (user returned to foreground quickly).
    func cancelDeferredPurge() {
        deferredPurgeWork?.cancel()
        deferredPurgeWork = nil
    }
}

// MARK: - Disk cache

/// Persists original image bytes in the Caches directory. Reads/writes are
/// synchronous file IO and are always called off the main actor (from the
/// detached load tasks in `ImagePipeline`).
final nonisolated class ImageDiskCache: @unchecked Sendable {
    static let shared = ImageDiskCache()

    private let directory: URL
    private let fileManager = FileManager.default

    private init() {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("ApexImageCache", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The on-disk cache directory, exposed so the Storage screen can sum its size.
    var directoryURL: URL {
        directory
    }

    func data(for key: String) -> Data? {
        try? Data(contentsOf: fileURL(for: key))
    }

    func store(_ data: Data, for key: String) {
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    func removeAll() {
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for key: String) -> URL {
        let hashed = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appendingPathComponent(hashed)
    }
}

// MARK: - Decoding

nonisolated enum ImageDecoder {
    /// Decodes raw image data into a platform image. When `maxPixelSize` is set,
    /// uses ImageIO to decode a thumbnail no larger than that on its longest
    /// edge — this both saves memory and is far faster than decoding full-size
    /// artwork only to draw it into a small card. `nil` decodes at full
    /// resolution (used for tvOS 4K heroes).
    ///
    /// IPTV channel logos are frequently small 8-bit grayscale+alpha PNGs. ImageIO
    /// thumbnails of those images decode to monochrome `CGImage`s that SwiftUI's
    /// `Image` (and sometimes `UIImageView`) fail to composite — the load succeeds
    /// but the UI slot stays blank. We decode small sources directly and flatten
    /// monochrome results to sRGB before caching.
    static func decode(_ data: Data, maxPixelSize: CGFloat?) -> PlatformImage? {
        guard let maxPixelSize else {
            return prepareForDisplay(PlatformImage(data: data))
        }

        #if canImport(UIKit)
            if let image = UIImage(data: data) {
                let pixelWidth = image.size.width * image.scale
                let pixelHeight = image.size.height * image.scale
                if max(pixelWidth, pixelHeight) <= maxPixelSize {
                    return prepareForDisplay(image)
                }
            }
        #else
            if let image = NSImage(data: data) {
                if max(image.size.width, image.size.height) <= maxPixelSize {
                    return prepareForDisplay(image)
                }
            }
        #endif

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return prepareForDisplay(PlatformImage(data: data))
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return prepareForDisplay(PlatformImage(data: data))
        }

        #if canImport(UIKit)
            return prepareForDisplay(UIImage(cgImage: cgImage, scale: 1, orientation: .up))
        #else
            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            return prepareForDisplay(NSImage(cgImage: cgImage, size: NSSize(width: width, height: height)))
        #endif
    }

    #if canImport(UIKit)
        private static func prepareForDisplay(_ image: UIImage?) -> UIImage? {
            guard let image else { return nil }
            guard let cgImage = image.cgImage else {
                return image.withRenderingMode(.alwaysOriginal)
            }
            guard cgImage.colorSpace?.model == .monochrome else {
                return image.withRenderingMode(.alwaysOriginal)
            }
            let size = image.size
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            format.opaque = false
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }.withRenderingMode(.alwaysOriginal)
        }
    #else
        private static func prepareForDisplay(_ image: NSImage?) -> NSImage? {
            guard let image else { return nil }
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                image.isTemplate = false
                return image
            }
            guard cgImage.colorSpace?.model == .monochrome else {
                image.isTemplate = false
                return image
            }
            let width = cgImage.width
            let height = cgImage.height
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let rgb = ({
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                return context.makeImage()
            })() else {
                image.isTemplate = false
                return image
            }
            let flattened = NSImage(cgImage: rgb, size: NSSize(width: width, height: height))
            flattened.isTemplate = false
            return flattened
        }
    #endif
}

private nonisolated extension PlatformImage {
    /// Rough decoded size in bytes (w × h × 4) used as the `NSCache` cost.
    var approximateByteCost: Int {
        #if canImport(UIKit)
            let pixels = size.width * size.height * scale * scale
        #else
            let pixels = size.width * size.height
        #endif
        return Int(pixels) * 4
    }
}

// MARK: - Native image view

/// Renders a decoded platform image outside SwiftUI's `Image` pipeline. Channel
/// logos inside `Button` labels in lazy stacks are prone to drawing blank on
/// macOS (especially when `NSImage.size` is `.zero`) and under global `.tint`.
struct PlatformImageView: View {
    let image: PlatformImage

    var body: some View {
        #if canImport(UIKit)
            PlatformImageViewRepresentable(image: image)
        #else
            PlatformImageViewRepresentable(image: image)
        #endif
    }
}

#if canImport(UIKit)
    private struct PlatformImageViewRepresentable: UIViewRepresentable {
        let image: UIImage

        func makeUIView(context: Context) -> UIImageView {
            let view = UIImageView()
            view.contentMode = .scaleAspectFit
            view.clipsToBounds = true
            view.isUserInteractionEnabled = false
            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            return view
        }

        func updateUIView(_ view: UIImageView, context: Context) {
            view.image = image.withRenderingMode(.alwaysOriginal)
        }
    }
#else
    private struct PlatformImageViewRepresentable: NSViewRepresentable {
        let image: NSImage

        func makeNSView(context: Context) -> NSImageView {
            let view = NSImageView()
            view.imageScaling = .scaleProportionallyUpOrDown
            view.imageAlignment = .alignCenter
            view.setContentHuggingPriority(.defaultLow, for: .horizontal)
            view.setContentHuggingPriority(.defaultLow, for: .vertical)
            return view
        }

        func updateNSView(_ view: NSImageView, context: Context) {
            image.isTemplate = false
            view.image = image
        }
    }
#endif
