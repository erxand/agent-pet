import CoreGraphics
import Testing
@testable import agent_pet

@Suite("a pet that moves to another display keeps its lane")
struct LaneCarryTests {
    private let laptop = CGRect(x: 0, y: 25, width: 1440, height: 875)
    private let monitor = CGRect(x: 1440, y: 0, width: 2560, height: 1415)

    @Test func theLaneFractionIsKept() {
        let home = LaneLayout.homeHorizontalCenter(laneIndex: 0, laneCount: 3, screenFrame: laptop)
        let carried = LaneLayout.carriedHorizontalCenter(home, from: laptop, to: monitor)
        #expect(abs(carried - LaneLayout.homeHorizontalCenter(laneIndex: 0, laneCount: 3, screenFrame: monitor)) < 0.001)
    }

    @Test func theSameFrameLeavesTheHomeAlone() {
        #expect(LaneLayout.carriedHorizontalCenter(500, from: monitor, to: monitor) == 500)
    }

    @Test func aFrameWithNoWidthCentersThePet() {
        let empty = CGRect(x: 10, y: 10, width: 0, height: 0)
        #expect(LaneLayout.carriedHorizontalCenter(500, from: empty, to: monitor) == monitor.midX)
    }
}
