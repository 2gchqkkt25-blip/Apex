import Foundation
@testable import Apex
import Testing

@MainActor
struct PlaybackSessionTests {
    init() {
        PlaybackSession.resetForTests()
    }

    @Test func `claiming a new session stops the previous one`() {
        var firstStopped = false
        var secondStopped = false
        _ = PlaybackSession.becomeActive { firstStopped = true }
        #expect(PlaybackSession.isActive)
        _ = PlaybackSession.becomeActive { secondStopped = true }
        #expect(firstStopped)
        #expect(!secondStopped)
        #expect(PlaybackSession.isActive)
    }

    @Test func `resigning an old token does not clear a newer session`() {
        var firstStopped = false
        var secondStopped = false
        let first = PlaybackSession.becomeActive { firstStopped = true }
        let second = PlaybackSession.becomeActive { secondStopped = true }
        PlaybackSession.resign(first)
        #expect(PlaybackSession.isActive)
        #expect(!secondStopped)
        PlaybackSession.resign(second)
        #expect(!PlaybackSession.isActive)
        #expect(firstStopped)
    }

    @Test func `stopActive runs the current handler once`() {
        var stops = 0
        _ = PlaybackSession.becomeActive { stops += 1 }
        PlaybackSession.stopActive()
        PlaybackSession.stopActive()
        #expect(stops == 1)
        #expect(!PlaybackSession.isActive)
    }
}
