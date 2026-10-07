import CoreGraphics
import Foundation
import Testing
@testable import AgentPetCore
@testable import agent_pet

private final class StrollRandom {
    private var generator: SeededGenerator

    init(seed: UInt64) {
        generator = SeededGenerator(seed: seed)
    }

    func next() -> Double {
        Double.random(in: 0..<1, using: &generator)
    }
}

@Suite("pets wander like simple game characters")
struct StrollTests {
    private static let tick = 1.0 / 30.0

    private func wanderingAnimator(halfWidth: CGFloat, seed: UInt64) -> PetAnimator {
        let random = StrollRandom(seed: seed)
        let animator = PetAnimator(random: { random.next() })
        animator.limitWander(to: halfWidth)
        for _ in 0..<30 { animator.advance(elapsedSeconds: StrollTests.tick, mood: .ready) }
        return animator
    }

    @Test func mostStrollsAreShortAndSomeCrossTheLane() {
        let random = StrollRandom(seed: 7)
        let halfWidth: CGFloat = 1200
        var distances: [CGFloat] = []
        var position: CGFloat = 0
        var heading: CGFloat = 1
        for _ in 0..<2000 {
            let destination = Stroll.destination(from: position, halfWidth: halfWidth, heading: heading, blockedHeading: nil) { random.next() }
            #expect(destination >= -halfWidth && destination <= halfWidth)
            distances.append(abs(destination - position))
            heading = destination < position ? -1 : 1
            position = destination
        }
        let short = distances.filter { distance in distance <= Stroll.unitInPoints * Stroll.shortStrollUnits.upperBound }.count
        let long = distances.filter { distance in distance >= 2 * halfWidth * 0.3 }.count
        #expect(Double(short) / Double(distances.count) > 0.7)
        #expect(Double(long) / Double(distances.count) > 0.05)
        #expect(Double(long) / Double(distances.count) < 0.25)
        let sortedShort = distances.filter { distance in distance <= Stroll.unitInPoints * Stroll.shortStrollUnits.upperBound }.sorted()
        #expect(sortedShort[sortedShort.count / 2] < Stroll.unitInPoints * 2.5)
    }

    @Test func aDestinationNeverLeavesTheRange() {
        let random = StrollRandom(seed: 11)
        for _ in 0..<5000 {
            let halfWidth = CGFloat(random.next()) * 600
            let position = (CGFloat(random.next()) * 2 - 1) * halfWidth
            let heading: CGFloat = random.next() < 0.5 ? -1 : 1
            let blocked: CGFloat? = random.next() < 0.2 ? heading : nil
            let destination = Stroll.destination(from: position, halfWidth: halfWidth, heading: heading, blockedHeading: blocked) { random.next() }
            #expect(destination >= -halfWidth - 0.001 && destination <= halfWidth + 0.001)
        }
    }

    @Test func nearAnEdgeTheNextStrollMostlyHeadsBackInward() {
        let random = StrollRandom(seed: 13)
        let halfWidth: CGFloat = 800
        for position in [CGFloat(700), -700, 780, -780] {
            let outward: CGFloat = position > 0 ? 1 : -1
            var inward = 0
            for _ in 0..<1000 {
                let destination = Stroll.destination(from: position, halfWidth: halfWidth, heading: outward, blockedHeading: nil) { random.next() }
                if (destination - position) * outward < 0 { inward += 1 }
            }
            #expect(inward > 800, "at \(position): \(inward) of 1000 inward")
        }
        var keeps = 0
        for _ in 0..<1000 {
            let destination = Stroll.destination(from: 0, halfWidth: halfWidth, heading: 1, blockedHeading: nil) { random.next() }
            if destination > 0 { keeps += 1 }
        }
        #expect(keeps > 600 && keeps < 800)
    }

    @Test func aBlockedPetStrollsTheOtherWayNext() {
        let random = StrollRandom(seed: 17)
        for _ in 0..<200 {
            let destination = Stroll.destination(from: 0, halfWidth: 500, heading: 1, blockedHeading: 1) { random.next() }
            #expect(destination < 0)
        }
    }

    @Test func aLonePetOnAWideScreenCoversItsWholeRangeAndNeverLeavesIt() {
        let halfWidth: CGFloat = (2560 - 128) / 2
        let animator = wanderingAnimator(halfWidth: halfWidth, seed: 106)
        var visited = Set<Int>()
        for _ in 0..<(30 * 60 * 30) {
            animator.advance(elapsedSeconds: StrollTests.tick, mood: .ready)
            let offset = animator.horizontalOffsetFromHome
            #expect(abs(offset) <= halfWidth)
            visited.insert(min(19, Int((offset + halfWidth) / (2 * halfWidth) * 20)))
        }
        #expect(visited.count == 20)
    }

    @Test func aNarrowLaneStillWorksWithoutJitter() {
        for halfWidth in [CGFloat(0), 6, 30] {
            let animator = wanderingAnimator(halfWidth: halfWidth, seed: 3)
            var reversals = 0
            var lastDirection: CGFloat = 0
            var previous = animator.horizontalOffsetFromHome
            for _ in 0..<(30 * 120) {
                animator.advance(elapsedSeconds: StrollTests.tick, mood: .ready)
                let offset = animator.horizontalOffsetFromHome
                #expect(abs(offset) <= halfWidth + 0.001)
                if offset != previous {
                    let direction: CGFloat = offset > previous ? 1 : -1
                    if lastDirection != 0 && direction != lastDirection { reversals += 1 }
                    lastDirection = direction
                }
                previous = offset
            }
            #expect(reversals < 60, "half width \(halfWidth): \(reversals) reversals in 2 minutes")
            if halfWidth == 0 { #expect(previous == 0) }
        }
    }

    static func lookAroundShare(seed: UInt64, minutes: Int) -> (idlePauses: Int, lookArounds: Int) {
        let random = StrollRandom(seed: seed)
        let animator = PetAnimator(random: { random.next() })
        animator.limitWander(to: 600)
        var idlePauses = 0
        var lookArounds = 0
        var previousAnimation = animator.animationName
        var facingAtPauseStart = animator.facingLeft
        var lookedThisPause = false
        for _ in 0..<(30 * 60 * minutes) {
            animator.advance(elapsedSeconds: StrollTests.tick, mood: .ready)
            let animation = animator.animationName
            let resting = animator.strollDestination == nil
            if resting && animation == .idle && previousAnimation != .idle {
                idlePauses += 1
                facingAtPauseStart = animator.facingLeft
                lookedThisPause = false
            } else if resting && animation == .idle && !lookedThisPause && animator.facingLeft != facingAtPauseStart {
                lookArounds += 1
                lookedThisPause = true
            }
            previousAnimation = resting ? animation : .walk
        }
        return (idlePauses, lookArounds)
    }

    @Test func aboutOneIdlePauseInFiveLooksAround() {
        let share = StrollTests.lookAroundShare(seed: 21, minutes: 20)
        #expect(share.idlePauses > 60)
        let fraction = Double(share.lookArounds) / Double(share.idlePauses)
        #expect(fraction > 0.08 && fraction < 0.34, "\(share)")
    }

    private func strollingAnimator(seed: UInt64) -> PetAnimator {
        let animator = wanderingAnimator(halfWidth: 600, seed: seed)
        for _ in 0..<(30 * 30) where animator.strollDestination == nil {
            animator.advance(elapsedSeconds: StrollTests.tick, mood: .ready)
        }
        #expect(animator.strollDestination != nil)
        return animator
    }

    @Test func aBlockedStrollStandsIdleGivesUpWithinASecondAndHeadsTheOtherWayNext() {
        for seed in UInt64(1)...30 {
            checkBlockedStroll(seed: seed)
        }
    }

    private func checkBlockedStroll(seed: UInt64) {
        let animator = strollingAnimator(seed: seed)
        let heading: CGFloat = (animator.strollDestination ?? 0) < animator.horizontalOffsetFromHome ? -1 : 1
        var blockedTicks = 0
        while animator.strollDestination != nil && blockedTicks < 120 {
            animator.advance(elapsedSeconds: StrollTests.tick, mood: .ready) { _ in false }
            blockedTicks += 1
            if animator.strollDestination != nil { #expect(animator.animationName == .idle) }
        }
        #expect(blockedTicks <= Int((PetAnimator.strollGiveUpInSeconds / StrollTests.tick).rounded(.up)) + 1)
        for _ in 0..<(30 * 30) where animator.strollDestination == nil {
            animator.advance(elapsedSeconds: StrollTests.tick, mood: .ready)
        }
        let next = (animator.strollDestination ?? 0) - animator.horizontalOffsetFromHome
        #expect(next * heading < 0, "seed \(seed)")
    }

    @Test func aBriefBlockResumesTheSameStroll() {
        let animator = strollingAnimator(seed: 9)
        let destination = animator.strollDestination
        for _ in 0..<10 { animator.advance(elapsedSeconds: StrollTests.tick, mood: .ready) { _ in false } }
        #expect(animator.animationName == .idle)
        #expect(animator.strollDestination == destination)
        animator.advance(elapsedSeconds: StrollTests.tick, mood: .ready)
        #expect(animator.animationName == .walk)
        #expect(animator.strollDestination == destination)
    }

    @Test func aRangeNarrowerThanTheShortestStrollIsNeverWalked() {
        let animator = wanderingAnimator(halfWidth: 3, seed: 2)
        for _ in 0..<(30 * 60) {
            animator.advance(elapsedSeconds: StrollTests.tick, mood: .ready)
            #expect(animator.animationName != .walk)
        }
    }

    @Test func aPetNeverWalksBackwardsAfterItsLaneMovesMidStroll() {
        for seed in UInt64(1)...40 {
            let animator = strollingAnimator(seed: seed)
            for _ in 0..<5 { animator.advance(elapsedSeconds: StrollTests.tick, mood: .ready) }
            animator.limitWander(to: 1800)
            let destination = animator.strollDestination ?? 0
            animator.moveHome(by: 2 * (animator.horizontalOffsetFromHome - destination))
            var previous = animator.horizontalOffsetFromHome
            for _ in 0..<(30 * 20) {
                animator.advance(elapsedSeconds: StrollTests.tick, mood: .ready)
                let moved = animator.horizontalOffsetFromHome - previous
                if moved != 0 { #expect((moved < 0) == animator.facingLeft, "seed \(seed)") }
                previous = animator.horizontalOffsetFromHome
            }
        }
    }

    @Test func standingSomewhereNewDropsTheStroll() {
        let animator = strollingAnimator(seed: 4)
        animator.stand(atHorizontalOffsetFromHome: -100)
        #expect(animator.strollDestination == nil)
        animator.advance(elapsedSeconds: StrollTests.tick, mood: .ready)
        #expect(animator.horizontalOffsetFromHome == -100)
    }

    @Test func noLookAroundOrNewStrollWhileAirborne() {
        let animator = wanderingAnimator(halfWidth: 600, seed: 8)
        for _ in 0..<(30 * 30) where animator.strollDestination != nil || animator.animationName == .walk {
            animator.advance(elapsedSeconds: StrollTests.tick, mood: .ready)
        }
        let facing = animator.facingLeft
        for _ in 0..<(30 * 10) {
            animator.advance(elapsedSeconds: StrollTests.tick, mood: .ready, airborne: true)
            #expect(animator.facingLeft == facing)
            #expect(animator.strollDestination == nil)
        }
        for _ in 0..<(30 * 10) where animator.strollDestination == nil {
            animator.advance(elapsedSeconds: StrollTests.tick, mood: .ready)
        }
        #expect(animator.strollDestination != nil)
    }
}
