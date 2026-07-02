import Foundation
import Testing
@testable import Apex

@Suite struct IntroDBClientTests {
    @Test func `normalizedIMDbID adds tt prefix`() {
        #expect(IntroDBClient.normalizedIMDbID("0903747") == "tt0903747")
        #expect(IntroDBClient.normalizedIMDbID("tt0903747") == "tt0903747")
    }

    @Test func `hasSkippableOpener ignores outro only`() {
        let outroOnly = IntroSegments(
            intro: nil,
            recap: nil,
            outro: IntroSegments.Segment(start: 100, end: 200)
        )
        #expect(outroOnly.hasSkippableOpener == false)

        let withIntro = IntroSegments(
            intro: IntroSegments.Segment(start: 10, end: 90),
            recap: nil,
            outro: IntroSegments.Segment(start: 100, end: 200)
        )
        #expect(withIntro.hasSkippableOpener == true)
    }
}
