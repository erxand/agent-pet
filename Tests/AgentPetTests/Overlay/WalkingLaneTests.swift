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
        #expect(animator.horizontalOffsetFromHome == -animator.wanderHalfWidth)
        #expect(ticks > 150)
        for _ in 0..<600 {
            animator.advance(elapsedSeconds: WalkingLaneTests.tick, mood: .ready)
            #expect(abs(animator.horizontalOffsetFromHome) <= animator.wanderHalfWidth)
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
        #expect(!LaneLayout.allowsStep(from: 500, to: 521, neighbour: 600, minimumGap: 80))
        #expect(LaneLayout.allowsStep(from: 500, to: 519, neighbour: 600, minimumGap: 80))
        #expect(LaneLayout.allowsStep(from: 560, to: 559, neighbour: 600, minimumGap: 80))
        #expect(!LaneLayout.allowsStep(from: 560, to: 561, neighbour: 600, minimumGap: 80))
        #expect(!LaneLayout.allowsStep(from: 580, to: 640, neighbour: 600, minimumGap: 80))
    }

    @Test func aNewcomerTakesALeftoverLane() {
        let lanes = LaneLayout.laneCenters(count: 3, screenFrame: screen)
        #expect(LaneLayout.assignedLanes(currentCenters: [nil, 300, 1100], laneCenters: lanes) == [1, 0, 2])
    }

    @Test func aPetFollowsTheFocusedDisplayToItsLaneThere() {
        let laptop = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let monitor = CGRect(x: 1440, y: 0, width: 2560, height: 1415)
        let home = LaneLayout.homeHorizontalCenter(laneIndex: 1, laneCount: 3, screenFrame: laptop)
        let carried = LaneLayout.carriedHorizontalCenter(home, from: laptop, to: monitor)
        #expect(carried == LaneLayout.homeHorizontalCenter(laneIndex: 1, laneCount: 3, screenFrame: monitor))
        #expect(monitor.contains(CGPoint(x: carried, y: monitor.midY)))
    }

    @Test func petsAtTheEdgesOfTheirWanderStillKeepTheGroundGap() {
        for laneCount in 1...14 {
            let gap = LaneLayout.minimumGroundGap(widestPet: 128, laneCount: laneCount, screenFrame: screen)
            let wander = LaneLayout.wanderHalfWidth(laneCount: laneCount, screenFrame: screen, minimumGap: gap)
            let spacing = screen.width / CGFloat(laneCount)
            #expect(spacing - 2 * wander >= gap - 0.001)
        }
    }

    @Test func aWalkerBehindAPetWithAQuestionGetsHome() {
        let gap: CGFloat = 77
        let walker = grounded()
        let asker = grounded()
        asker.limitWander(to: 120)
        walker.limitWander(to: 40)
        let askerHome: CGFloat = 700
        var walkerHome: CGFloat = 300
        asker.stand(atHorizontalOffsetFromHome: -120)
        asker.advance(elapsedSeconds: WalkingLaneTests.tick, mood: .needsInput)
        asker.limitWander(to: 40)
        walker.stand(atHorizontalOffsetFromHome: 0)
        walker.moveHome(by: 250)
        walkerHome += 250
        var ticks = 0
        while walker.isWalkingHome && ticks < 3000 {
            let askerX = askerHome + asker.horizontalOffsetFromHome
            walker.advance(elapsedSeconds: WalkingLaneTests.tick, mood: .ready) { offset in
                let allowed = LaneLayout.allowsStep(
                    from: walkerHome + walker.horizontalOffsetFromHome,
                    to: walkerHome + offset,
                    neighbour: askerX,
                    minimumGap: gap
                )
                if !allowed && walker.isWalkingHome { asker.walkHomeNow() }
                return allowed
            }
            asker.advance(elapsedSeconds: WalkingLaneTests.tick, mood: .needsInput)
            #expect(askerHome + asker.horizontalOffsetFromHome - (walkerHome + walker.horizontalOffsetFromHome) >= gap - 0.001)
            ticks += 1
        }
        #expect(walkerHome == 550)
        #expect(!walker.isWalkingHome)
        #expect(walker.horizontalOffsetFromHome == -walker.wanderHalfWidth)
        #expect(asker.horizontalOffsetFromHome == -asker.wanderHalfWidth)
    }

    @Test func aLonePetsLaneIsTheWholeWidthAndItsWanderReachesBothEnds() {
        let widest: CGFloat = 96
        let gap = LaneLayout.minimumGroundGap(widestPet: widest, laneCount: 1, screenFrame: screen)
        let wander = LaneLayout.wanderHalfWidth(laneCount: 1, screenFrame: screen, minimumGap: gap)
        let home = LaneLayout.homeHorizontalCenter(laneIndex: 0, laneCount: 1, screenFrame: screen)
        #expect(LaneLayout.lane(index: 0, laneCount: 1, screenFrame: screen) == screen.minX...screen.maxX)
        #expect(home == screen.midX)
        #expect(home - wander == screen.minX + (widest + LaneLayout.neighbourPadding) / 2)
        #expect(home + wander == screen.maxX - (widest + LaneLayout.neighbourPadding) / 2)

        let animator = grounded()
        animator.limitWander(to: wander)
        var lowest: CGFloat = 0
        var highest: CGFloat = 0
        for _ in 0..<(30 * 600) {
            animator.advance(elapsedSeconds: WalkingLaneTests.tick, mood: .ready)
            lowest = min(lowest, animator.horizontalOffsetFromHome)
            highest = max(highest, animator.horizontalOffsetFromHome)
            #expect(abs(animator.horizontalOffsetFromHome) <= wander)
        }
        #expect(highest - lowest > wander)
    }

    @Test func nLanesTileTheWidthWithNoGapsAndNoOverlapAndKeepTheGroundGap() {
        for laneCount in 1...12 {
            let lanes = (0..<laneCount).map { index in LaneLayout.lane(index: index, laneCount: laneCount, screenFrame: screen) }
            #expect(lanes.first?.lowerBound == screen.minX)
            #expect(abs((lanes.last?.upperBound ?? 0) - screen.maxX) < 0.001)
            for (left, right) in zip(lanes, lanes.dropFirst()) {
                #expect(abs(left.upperBound - right.lowerBound) < 0.001)
            }
            let gap = LaneLayout.minimumGroundGap(widestPet: 96, laneCount: laneCount, screenFrame: screen)
            let wander = LaneLayout.wanderHalfWidth(laneCount: laneCount, screenFrame: screen, minimumGap: gap)
            let centers = LaneLayout.laneCenters(count: laneCount, screenFrame: screen)
            for (index, center) in centers.enumerated() {
                #expect(abs(center - (lanes[index].lowerBound + lanes[index].upperBound) / 2) < 0.001)
                #expect(center - wander >= lanes[index].lowerBound + gap / 2 - 0.001)
                #expect(center + wander <= lanes[index].upperBound - gap / 2 + 0.001)
            }
            for (left, right) in zip(centers, centers.dropFirst()) {
                #expect((right - wander) - (left + wander) >= gap - 0.001)
            }
        }
    }

    @Test func theGroundGapNeverKeepsAPetFromItsLane() {
        let crowded = LaneLayout.minimumGroundGap(widestPet: 128, laneCount: 12, screenFrame: screen)
        let laneSpacing = screen.width / 12
        #expect(crowded < laneSpacing)
        #expect(LaneLayout.minimumGroundGap(widestPet: 128, laneCount: 2, screenFrame: screen) == 128 + LaneLayout.neighbourPadding)
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

    @Test func aHeadOnBounceLosesALittleSpeedAndNeverGains() {
        var first = SpaceMotion(launchingFrom: CGPoint(x: 500, y: 400), seed: 3)
        var second = SpaceMotion(launchingFrom: CGPoint(x: 560, y: 400), seed: 4)
        let firstSpeed = hypot(first.velocity.dx, first.velocity.dy)
        let secondSpeed = hypot(second.velocity.dx, second.velocity.dy)
        first.bounce(off: &second, minimumDistance: 80)
        let energyBefore = firstSpeed * firstSpeed + secondSpeed * secondSpeed
        let energyAfter = pow(hypot(first.velocity.dx, first.velocity.dy), 2) + pow(hypot(second.velocity.dx, second.velocity.dy), 2)
        #expect(energyAfter <= energyBefore + 0.001)
    }

    @Test func aLongFloatOfBouncingPetsStaysAtCruisingSpeed() {
        let small = SpaceArea(lowestCenter: CGPoint(x: 40, y: 40), highestCenter: CGPoint(x: 400, y: 300))
        var motions = (0..<4).map { index in
            SpaceMotion(launchingFrom: CGPoint(x: 100 + CGFloat(index) * 60, y: 150), seed: UInt64(index + 10))
        }
        let cruise = motions.map { motion in motion.cruiseSpeed }
        for _ in 0..<(30 * 120) {
            SpaceMotion.collide(&motions) { _, _ in 80 }
            for index in motions.indices {
                motions[index].advance(elapsedSeconds: 1.0 / 30.0, area: small, homeCenterX: 0)
            }
        }
        for (motion, cruiseSpeed) in zip(motions, cruise) {
            let speed = hypot(motion.velocity.dx, motion.velocity.dy)
            #expect(speed < SpaceMotion.maximumBounceSpeed * 0.9)
            #expect(abs(speed - cruiseSpeed) < cruiseSpeed * 0.5)
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
