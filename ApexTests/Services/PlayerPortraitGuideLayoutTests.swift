import Foundation
@testable import Apex
import Testing

struct PlayerPortraitGuideLayoutTests {
    @Test func `portrait with guide open pins video to the top`() {
        let canvas = CGSize(width: 393, height: 852)
        #expect(PlayerPortraitGuideLayout.pinsVideoToTop(guideOpen: true, canvas: canvas))
        #expect(!PlayerPortraitGuideLayout.pinsVideoToTop(guideOpen: false, canvas: canvas))
        #expect(!PlayerPortraitGuideLayout.pinsVideoToTop(guideOpen: true, canvas: canvas, aspectFill: true))
    }

    @Test func `landscape keeps the video full screen`() {
        let canvas = CGSize(width: 852, height: 393)
        #expect(!PlayerPortraitGuideLayout.pinsVideoToTop(guideOpen: true, canvas: canvas))
    }

    @Test func `video band is a 16 by 9 slice of the width`() {
        let canvas = CGSize(width: 400, height: 800)
        #expect(PlayerPortraitGuideLayout.videoBandHeight(in: canvas) == 225)
    }
}
