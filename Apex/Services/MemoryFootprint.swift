//
//  MemoryFootprint.swift
//  Apex
//
//  Reads the same `phys_footprint` figure the jetsam daemon uses to decide
//  when to kill a process — far more accurate than resident size, which
//  undercounts compressed/purgeable memory. Used to log real numbers during
//  Apple TV HD playback and browsing so a jetsam crash leaves a trail of *why*,
//  since the debugger itself is torn down before a jetsam kill reaches Xcode.
//
//  Deliberately just this one `task_info` call. An earlier version also walked
//  the task's VM map with `vm_region_recurse_64` to break memory down by tag,
//  `vmmap`-style. Don't bring that back: every call takes the task's VM map
//  lock, descending into the shared-cache submaps produces a huge number of
//  iterations, and the per-tag totals double-counted nested/shared regions
//  badly enough to be actively misleading (~940 MB reported against a real
//  148 MB footprint). On device it stalled every allocating thread and froze
//  the app. Use Instruments or a memory graph when a breakdown is needed.
//

import Darwin
import Foundation
import os
import OSLog

#if canImport(UIKit)
    import UIKit

    /// Counts the live view hierarchy so a leak that manifests as views never
    /// being torn down is visible as a number rather than inferred from a
    /// footprint curve.
    ///
    /// `replicants` specifically counts `_UIReplicantView` — the snapshot view
    /// UIKit inserts to cross-fade a subtree. Each one owns a bitmap the size of
    /// the area it captured, so a full-screen snapshot on a 1080p Apple TV is
    /// ~8.3 MB. The console warning "Adding '_UIReplicantView' as a subview of
    /// UIHostingController.view is not supported and may result in a broken view
    /// hierarchy" says UIKit is inserting these into a SwiftUI-hosted tree it
    /// can't correctly unwind, so the question is whether they are removed after
    /// the animation. A count that climbs and never falls answers that.
    enum ViewHierarchyProbe {
        struct Counts: Sendable {
            var total = 0
            var replicants = 0
        }

        @MainActor
        static func current() -> Counts {
            var counts = Counts()
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows {
                    walk(window, into: &counts, depth: 0)
                }
            }
            return counts
        }

        /// Depth-capped so a pathological hierarchy can't turn the probe itself
        /// into the stall the previous VM-map diagnostic was.
        @MainActor
        private static func walk(_ view: UIView, into counts: inout Counts, depth: Int) {
            guard depth < 80 else { return }
            counts.total += 1
            if NSStringFromClass(type(of: view)).contains("Replicant") {
                counts.replicants += 1
            }
            for subview in view.subviews {
                walk(subview, into: &counts, depth: depth + 1)
            }
        }
    }
#endif

enum MemoryFootprint {
    /// Current physical memory footprint in bytes, or `nil` if the query failed.
    static var currentBytes: UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }

    static var currentMB: Double? {
        guard let bytes = currentBytes else { return nil }
        return Double(bytes) / 1024 / 1024
    }

    /// Bytes currently held by live `malloc` blocks across every zone.
    ///
    /// Logged next to the footprint because together the two split a leak in
    /// half, which one number alone cannot do: heap allocations (anything Swift
    /// or Obj-C code holds — model objects, images, buffers) count toward both,
    /// whereas CoreMedia/IOSurface video buffers are mapped rather than
    /// malloc'd and so raise only the footprint. A footprint that climbs while
    /// this stays flat therefore means the growth is in the media stack, not in
    /// app code — and vice versa. Unlike the VM-map walk described above this is
    /// a single cheap aggregate read, not a region traversal.
    static var mallocInUseBytes: UInt64? {
        var stats = malloc_statistics_t()
        // A nil zone aggregates every zone.
        malloc_zone_statistics(nil, &stats)
        return UInt64(stats.size_in_use)
    }

    static var mallocInUseMB: Double? {
        guard let bytes = mallocInUseBytes else { return nil }
        return Double(bytes) / 1024 / 1024
    }

    private static let monitorStarted = OSAllocatedUnfairLock(initialState: false)

    /// Set `APEX_MEMORY_TRACE=1` in the scheme's environment to force the trace
    /// on a device/simulator that isn't memory-constrained, so a leak that
    /// reproduces everywhere can be chased without an Apple TV HD on hand.
    private static var traceForced: Bool {
        ProcessInfo.processInfo.environment["APEX_MEMORY_TRACE"] == "1"
    }

    /// Logs the footprint every `interval` seconds for the whole session on
    /// memory-constrained devices (Apple TV HD). Playback has its own timer;
    /// this one exists because jetsam also happens while *browsing*, and
    /// without a baseline trace there's no way to tell "browsing is already at
    /// 1.2 GB before playback even starts" apart from "playback allocated it
    /// all". Cheap: one `task_info` call per tick.
    static func startMonitoringIfConstrained(interval: Duration = .seconds(5)) {
        guard DeviceMemoryTier.current.isConstrained || traceForced else { return }
        let shouldStart = monitorStarted.withLock { started -> Bool in
            if started { return false }
            started = true
            return true
        }
        guard shouldStart else { return }

        Task.detached(priority: .utility) {
            while true {
                try? await Task.sleep(for: interval)
                guard let mb = currentMB else { continue }
                let heap = mallocInUseMB ?? 0
                #if canImport(UIKit)
                    let views = await ViewHierarchyProbe.current()
                    // swiftlint:disable:next line_length
                    Logger.memory.log("Session footprint: \(mb, format: .fixed(precision: 1), privacy: .public) MB heap=\(heap, format: .fixed(precision: 1), privacy: .public) MB views=\(views.total, privacy: .public) replicants=\(views.replicants, privacy: .public)")
                #else
                    Logger.memory.log("Session footprint: \(mb, format: .fixed(precision: 1), privacy: .public) MB heap=\(heap, format: .fixed(precision: 1), privacy: .public) MB")
                #endif
            }
        }
    }
}
