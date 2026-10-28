import CoreGraphics
import Testing
@testable import NotinhasCore

private let laptop = CGRect(x: 0, y: 0, width: 1440, height: 900)

@Suite struct HotCornerScreen {
    @Test func findsScreenWhenPointerIsInItsBottomRightCorner() {
        #expect(HotCorner.screen(at: CGPoint(x: 1439, y: 1), among: [laptop]) == laptop)
        #expect(HotCorner.screen(at: CGPoint(x: 1440, y: 0), among: [laptop]) == laptop)
    }

    @Test func ignoresEdgesAndOtherCorners() {
        #expect(HotCorner.screen(at: CGPoint(x: 1439, y: 40), among: [laptop]) == nil)
        #expect(HotCorner.screen(at: CGPoint(x: 1200, y: 1), among: [laptop]) == nil)
        #expect(HotCorner.screen(at: CGPoint(x: 1439, y: 899), among: [laptop]) == nil)
        #expect(HotCorner.screen(at: CGPoint(x: 0, y: 0), among: [laptop]) == nil)
    }

    @Test func skipsCornerLeadingToScreenOnTheRight() {
        let monitor = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        #expect(HotCorner.screen(at: CGPoint(x: 1439, y: 1), among: [laptop, monitor]) == nil)
        #expect(HotCorner.screen(at: CGPoint(x: 3359, y: 1), among: [laptop, monitor]) == monitor)
    }

    @Test func skipsCornerLeadingToScreenBelow() {
        let monitor = CGRect(x: 0, y: 900, width: 1280, height: 720)
        #expect(HotCorner.screen(at: CGPoint(x: 1279, y: 901), among: [laptop, monitor]) == nil)
        #expect(HotCorner.screen(at: CGPoint(x: 1439, y: 1), among: [laptop, monitor]) == laptop)
    }

    @Test func worksWithNegativeCoordinates() {
        let monitor = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        #expect(HotCorner.screen(at: CGPoint(x: -1, y: -299), among: [laptop, monitor]) == monitor)
    }
}
