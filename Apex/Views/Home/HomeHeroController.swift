//
//  HomeHeroController.swift
//  Apex
//
//  Shared carousel state for the home hero: horizontal paging artwork,
//  auto-advance clock, and crossfading title copy. Used by the inline
//  carousel on iPhone/macOS, the immersive iPad layout, and tvOS.
//

import SwiftUI

/// One rendered page in the carousel. Real items use their own `HeroItem.id`;
/// boundary clones reuse a mirrored item but carry a sentinel id so the scroll
/// position can distinguish a clone from the page it duplicates.
struct HeroSlot: Identifiable {
    let id: String
    let item: HeroItem
}

@MainActor @Observable
final class HomeHeroController {
    private(set) var items: [HeroItem] = []

    var currentID: String?
    var isInteracting = false

    /// Fill of the active page indicator (0…1). Driven by auto-advance and
    /// reset on every page change so the bar and slide jump stay in sync.
    private(set) var progress: Double = 0

    /// Which hero the overlay is showing. Lags the scroll position so copy
    /// fades out, swaps while invisible, then fades back in.
    private(set) var displayedID: String?
    private(set) var infoOpacity: Double = 1

    /// When true, auto-advance holds at zero (tvOS below-the-fold pause).
    var isPaused = false

    static let headCloneID = "hero-clone-head"
    static let tailCloneID = "hero-clone-tail"

    let autoAdvanceInterval: Duration = .seconds(6)

    var slots: [HeroSlot] {
        guard items.count > 1, let first = items.first, let last = items.last else {
            return items.map { HeroSlot(id: $0.id, item: $0) }
        }
        return [HeroSlot(id: Self.headCloneID, item: last)]
            + items.map { HeroSlot(id: $0.id, item: $0) }
            + [HeroSlot(id: Self.tailCloneID, item: first)]
    }

    var currentItemID: String? {
        guard let currentID else { return items.first?.id }
        return slots.first { $0.id == currentID }?.item.id ?? currentID
    }

    var currentHero: HeroItem? {
        items.first { $0.id == currentItemID } ?? items.first
    }

    var currentIndex: Int {
        items.firstIndex { $0.id == currentItemID } ?? 0
    }

    var displayedHero: HeroItem? {
        items.first { $0.id == displayedID } ?? currentHero
    }

    func configure(items: [HeroItem]) {
        self.items = items
        if currentID == nil || !slots.contains(where: { $0.id == currentID }) {
            currentID = items.first?.id
        }
        if displayedID == nil || !items.contains(where: { $0.id == displayedID }) {
            displayedID = items.first?.id
        }
        prefetchNeighbours()
    }

    func onAppear() {
        if displayedID == nil { displayedID = items.first?.id }
        if currentID == nil { currentID = items.first?.id }
        prefetchNeighbours()
    }

    func onCurrentItemChanged() {
        progress = 0
        prefetchNeighbours()
        crossfadeInfo()
    }

    func onScrollPhaseChange(_ newPhase: ScrollPhase) {
        isInteracting = newPhase == .tracking || newPhase == .interacting || newPhase == .decelerating
        if newPhase == .idle { normaliseClonePosition() }
    }

    /// One 50ms tick of the auto-advance clock. Returns `true` when the bar
    /// has filled and the caller should page.
    func tickAutoAdvance() -> Bool {
        guard items.count > 1 else { return false }
        if isInteracting || isPaused {
            progress = 0
            return false
        }
        if progress >= 1 {
            progress = 0
            return true
        }
        let total = Double(autoAdvanceInterval.components.seconds)
        progress = min(progress + 0.05 / total, 1)
        return false
    }

    func advance() {
        guard slots.count > 1 else { return }
        let index = slots.firstIndex { $0.id == currentID } ?? 1
        let next = slots[min(index + 1, slots.count - 1)].id
        withAnimation(.easeInOut(duration: 0.6)) { currentID = next }
    }

    func retreat() {
        guard slots.count > 1 else { return }
        let index = slots.firstIndex { $0.id == currentID } ?? 1
        let previous = slots[max(index - 1, 0)].id
        withAnimation(.easeInOut(duration: 0.6)) { currentID = previous }
    }

    func normaliseClonePosition() {
        guard let currentID else { return }
        if currentID == Self.headCloneID {
            self.currentID = items.last?.id
        } else if currentID == Self.tailCloneID {
            self.currentID = items.first?.id
        }
    }

    func prefetchNeighbours() {
        guard let currentItemID,
              let index = items.firstIndex(where: { $0.id == currentItemID })
        else { return }
        let count = items.count
        guard count > 1 else { return }
        let neighbours = [(index - 1 + count) % count, (index + 1) % count]
            .compactMap { items[$0].imageURL }
        guard !neighbours.isEmpty else { return }
        Task { await ImagePipeline.shared.prefetch(neighbours, maxPixelSize: nil) }
    }

    private func crossfadeInfo() {
        guard displayedID != currentItemID else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            infoOpacity = 0
        } completion: {
            self.displayedID = self.currentItemID
            withAnimation(.easeOut(duration: 0.45)) {
                self.infoOpacity = 1
            }
        }
    }
}
