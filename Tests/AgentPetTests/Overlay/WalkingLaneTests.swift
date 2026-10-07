import CoreGraphics
import Foundation
import Testing
import AgentPetCore
@testable import agent_pet

@Suite("pets walk between lanes and never pass through each other")
struct WalkingLaneTests {
    private static let tick = 1.0 / 30.0
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    private func grounded() -> PetAnimator {
        let animator = PetAnimator()
        for _ in 0..<30 { animator.advance(elapsedSeconds: WalkingLaneTests.tick, mood: .ready) }
        #expect(animator.groundPhase == .grounded)
        return animator
    }

    @Test func lanesFollowTheOrderPetsStandIn() {
        let lanes = LaneLayout.laneCenters(count: 3, screenFrame: screen)
        #expect(LaneLayout.assignedLanes(currentCenters: [1000, 200, 600], laneCenters: lanes) == [2, 0, 1])
        #expect(LaneLayout.assignedLanes(currentCenters: [1300, 100, 1200], laneCenters: lanes) == [2, 0, 1])
    }

    @Test func aNewcomerTakesTheLaneTheOthersLeaveFree() {
        let lanes = LaneLayout.laneCenters(count: 3, screenFrame: screen)
        #expect(LaneLayout.assignedLanes(currentCenters: [300, nil, 1100], laneCenters: lanes) == [0, 1, 2])
        #expect(LaneLayout.assignedLanes(currentCenters: [nil, 350, 700], laneCenters: lanes) == [2, 0, 1])
        #expect(LaneLayout.assignedLanes(currentCenters: [nil, nil], laneCenters: LaneLayout.laneCenters(count: 2, screenFrame: screen)) == [0, 1])
    }

    @Test func aLaneChangeIsWalkedAtWalkingSpeed() {
        let animator = grounded()
        let start = animator.horizontalOffsetFromHome
        animator.moveHome(by: 400)
        #expect(animator.horizontalOffsetFromHome == start - 400)
        #expect(animator.isWalkingHome)
        var previous = animator.horizontalOffsetFromHome
        var ticks = 0
        while animator.isWalkingHome && ticks < 2000 {
            animator.advance(elapsedSeconds: WalkingLaneTests.tick, mood: .ready)
            let step = abs(animator.horizontalOffsetFromHome - previous)
            #expect(step <= PetAnimator.walkSpeedInPointsPerSecond * CGFloat(WalkingLaneTests.tick) + 0.001)
            previous = animator.horizontalOffsetFromHome
            ticks += 1
        }
        #expect(!animator.isWalkingHome)
        #expect(animator.horizontalOffsetFromHome == 0)
        #expect(ticks > 200)
        for _ in 0..<600 {
            animator.advance(elapsedSeconds: WalkingLaneTests.tick, mood: .ready)
            #expect(abs(animator.horizontalOffsetFromHome) <= LaneLayout.wanderHalfWidth)
        }
    }

    @Test func aSmallLaneChangeKeepsWandering() {
        let animator = grounded()
        animator.moveHome(by: 20)
        #expect(!animator.isWalkingHome)
    }

    @Test func aPetWithAQuestionStillWalksToItsLane() {
        let animator = grounded()
        animator.moveHome(by: -300)
        animator.advance(elapsedSeconds: WalkingLaneTests.tick, mood: .needsInput)
        #expect(animator.animationName == .walk)
        #expect(animator.facingLeft)
        for _ in 0..<1000 where animator.isWalkingHome {
            animator.advance(elapsedSeconds: WalkingLaneTests.tick, mood: .needsInput)
        }
        animator.advance(elapsedSeconds: WalkingLaneTests.tick, mood: .needsInput)
        #expect(animator.animationName == .idle)
    }

    @Test func aBlockedPetRunsInPlace() {
        let animator = grounded()
        animator.moveHome(by: 300)
        let blockedAt = animator.horizontalOffsetFromHome
        for _ in 0..<60 {
            animator.advance(elapsedSeconds: WalkingLaneTests.tick, mood: .ready) { _ in false }
            #expect(animator.horizontalOffsetFromHome == blockedAt)
            #expect(animator.animationName == .walk)
        }
        animator.advance(elapsedSeconds: WalkingLaneTests.tick, mood: .ready)
        #expect(animator.horizontalOffsetFromHome != blockedAt)
    }

    @Test func aStepThatWouldOverlapANeighbourIsRefused() {
        let gap: (Int) -> CGFloat = { _ in 80 }
        #expect(!LaneLayout.allowsStep(from: 500, to: 521, neighbours: [600], minimumGap: gap))
        #expect(LaneLayout.allowsStep(from: 500, to: 519, neighbours: [600], minimumGap: gap))
        #expect(LaneLayout.allowsStep(from: 560, to: 559, neighbours: [600], minimumGap: gap))
        #expect(!LaneLayout.allowsStep(from: 560, to: 561, neighbours: [600], minimumGap: gap))
        #expect(!LaneLayout.allowsStep(from: 580, to: 640, neighbours: [600], minimumGap: gap))
    }

    @Test func theGroundGapNeverKeepsAPetFromItsLane() {
        let crowded = LaneLayout.minimumGroundGap(bodyWidths: (128, 128), laneCount: 12, screenFrame: screen)
        let laneSpacing = screen.width / 13
        #expect(crowded < laneSpacing)
        #expect(LaneLayout.minimumGroundGap(bodyWidths: (128, 128), laneCount: 2, screenFrame: screen) == 128 * LaneLayout.bodyWidthFraction)
    }
}

@Suite("floating pets bounce off each other")
struct FloatingBounceTests {
    private let area = SpaceArea(lowestCenter: CGPoint(x: 40, y: 40), highestCenter: CGPoint(x: 1400, y: 860))

    @Test func twoPetsThatTouchPushApartAndMoveAway() {
        var left = SpaceMotion(launchingFrom: CGPoint(x: 500, y: 400), seed: 1)
        var right = SpaceMotion(launchingFrom: CGPoint(x: 540, y: 400), seed: 2)
        var pair = [left, right]
        SpaceMotion.collide(&pair) { _, _ in 80 }
        left = pair[0]
        right = pair[1]
        #expect(right.center.x - left.center.x >= 80 - 0.001)
        let separating = (right.velocity.dx - left.velocity.dx)
        #expect(separating >= 0)
        for motion in pair {
            #expect(hypot(motion.velocity.dx, motion.velocity.dy) <= SpaceMotion.maximumBounceSpeed + 0.001)
        }
    }

    @Test func aHeadOnBounceIsALittleLively() {
        var first = SpaceMotion(launchingFrom: CGPoint(x: 500, y: 400), seed: 3)
        var second = SpaceMotion(launchingFrom: CGPoint(x: 560, y: 400), seed: 4)
        let approach = (first.velocity.dx - second.velocity.dx)
        first.bounce(off: &second, minimumDistance: 80)
        let departure = (second.velocity.dx - first.velocity.dx)
        if approach > 0 {
            #expect(departure > approach * 0.99)
        } else {
            #expect(departure >= -approach - 0.001)
        }
    }

    @Test func farApartPetsDoNotTouch() {
        let first = SpaceMotion(launchingFrom: CGPoint(x: 100, y: 400), seed: 5)
        let second = SpaceMotion(launchingFrom: CGPoint(x: 900, y: 400), seed: 6)
        var pair = [first, second]
        SpaceMotion.collide(&pair) { _, _ in 80 }
        #expect(pair == [first, second])
    }

    @Test func aFallingPetIsNotBounced() {
        var falling = SpaceMotion(launchingFrom: CGPoint(x: 500, y: 400), seed: 7)
        falling.returnToGround()
        var floatingPet = SpaceMotion(launchingFrom: CGPoint(x: 520, y: 400), seed: 8)
        let before = (falling, floatingPet)
        falling.bounce(off: &floatingPet, minimumDistance: 80)
        #expect(falling == before.0)
        #expect(floatingPet == before.1)
    }
}
