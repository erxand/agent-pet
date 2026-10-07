import CoreGraphics
import Foundation
import Testing
@testable import AgentPetCore
@testable import agent_pet

private final class TestWalker: LaneWalker {
    var homeHorizontalCenter: CGFloat
    let animator: PetAnimator
    let laneWidth: CGFloat = 120
    let windowWidth: CGFloat = 120
    var isInFlight = false

    init(home: CGFloat, offset: CGFloat = 0, random: @escaping () -> Double = { 0.99 }) {
        homeHorizontalCenter = home
        animator = PetAnimator(random: random)
        for _ in 0..<30 { animator.advance(elapsedSeconds: 1.0 / 30.0, mood: .ready) }
        animator.stand(atHorizontalOffsetFromHome: offset)
    }

    var standing: CGFloat { homeHorizontalCenter + animator.horizontalOffsetFromHome }
}

private final class SeededRandom {
    private var generator: SeededGenerator

    init(seed: UInt64) {
        generator = SeededGenerator(seed: seed)
    }

    func next() -> Double {
        Double.random(in: 0..<1, using: &generator)
    }
}

@Suite("lanes are divided again as pets come and go")
struct LaneRedivisionTests {
    private static let tick = 1.0 / 30.0
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let monitor = CGRect(x: 1440, y: 0, width: 2560, height: 1415)

    private func walkUntilSettled(_ walker: TestWalker) -> Bool {
        var previous = walker.animator.horizontalOffsetFromHome
        var walkedAtWalkingSpeed = true
        for _ in 0..<(30 * 60) where walker.animator.isWalkingHome {
            walker.animator.advance(elapsedSeconds: LaneRedivisionTests.tick, mood: .ready)
            let step = abs(walker.animator.horizontalOffsetFromHome - previous)
            if step > PetAnimator.walkSpeedInPointsPerSecond * CGFloat(LaneRedivisionTests.tick) + 0.001 { walkedAtWalkingSpeed = false }
            previous = walker.animator.horizontalOffsetFromHome
        }
        return walkedAtWalkingSpeed
    }

    @Test func aNewNeighbourSplitsTheWidthAndTheFirstPetWalksToTheNearEdgeOfItsHalf() {
        let first = TestWalker(home: screen.midX)
        _ = LaneRedivision.apply(to: [first], keepingStanding: [true], screenFrame: screen)
        first.animator.stand(atHorizontalOffsetFromHome: -680)
        let standing = first.standing
        let newcomer = TestWalker(home: screen.midX)

        let gap = LaneRedivision.apply(to: [first, newcomer], keepingStanding: [true, false], screenFrame: screen)
        #expect(first.standing == standing)
        #expect(first.homeHorizontalCenter == LaneLayout.homeHorizontalCenter(laneIndex: 0, laneCount: 2, screenFrame: screen))
        #expect(newcomer.homeHorizontalCenter == LaneLayout.homeHorizontalCenter(laneIndex: 1, laneCount: 2, screenFrame: screen))

        let third = TestWalker(home: screen.midX)
        _ = LaneRedivision.apply(to: [first, newcomer, third], keepingStanding: [true, true, false], screenFrame: screen)
        #expect(first.standing == standing)
        #expect(walkUntilSettled(first))
        #expect(!first.animator.isWalkingHome)
        #expect(abs(first.animator.horizontalOffsetFromHome) == first.animator.wanderHalfWidth)
        #expect(first.animator.horizontalOffsetFromHome < 0)
        #expect(gap > 0)
    }

    @Test func aPetThatLeavesGivesItsNeighbourTheWholeWidth() {
        let left = TestWalker(home: 360)
        let right = TestWalker(home: 1080)
        _ = LaneRedivision.apply(to: [left, right], keepingStanding: [true, true], screenFrame: screen)
        let standing = right.standing
        let gap = LaneRedivision.apply(to: [right], keepingStanding: [true], screenFrame: screen)
        #expect(right.standing == standing)
        #expect(right.homeHorizontalCenter == screen.midX)
        #expect(right.animator.wanderHalfWidth == (screen.width - gap) / 2)
        right.animator.advance(elapsedSeconds: LaneRedivisionTests.tick, mood: .ready)
        #expect(!right.animator.isWalkingHome)
        #expect(right.standing == standing)
    }

    @Test func aFloatingPetHoldsNoLaneAndTakesOneAgainWhenItLands() {
        let walker = TestWalker(home: 360)
        let floater = TestWalker(home: 1080)
        floater.isInFlight = true
        let floaterHome = floater.homeHorizontalCenter
        _ = LaneRedivision.apply(to: [walker, floater], keepingStanding: [true, true], screenFrame: screen)
        #expect(walker.homeHorizontalCenter == screen.midX)
        #expect(floater.homeHorizontalCenter == floaterHome)

        floater.isInFlight = false
        _ = LaneRedivision.apply(to: [walker, floater], keepingStanding: [true, true], screenFrame: screen)
        #expect(walker.homeHorizontalCenter == LaneLayout.homeHorizontalCenter(laneIndex: 0, laneCount: 2, screenFrame: screen))
        #expect(floater.homeHorizontalCenter == LaneLayout.homeHorizontalCenter(laneIndex: 1, laneCount: 2, screenFrame: screen))
    }

    @Test func movingToASmallerDisplayKeepsTheWholeWindowOnScreenSoThePetNeverRunsInPlace() {
        for offset in stride(from: CGFloat(-1270), through: 1270, by: 127) {
            let walker = TestWalker(home: monitor.midX)
            _ = LaneRedivision.apply(to: [walker], keepingStanding: [true], screenFrame: monitor)
            walker.animator.stand(atHorizontalOffsetFromHome: offset)
            LaneRedivision.carry(walker, from: monitor, to: screen)
            _ = LaneRedivision.apply(to: [walker], keepingStanding: [true], screenFrame: screen)
            let halfWindow = walker.windowWidth / 2
            #expect(walker.standing >= screen.minX + halfWindow - 0.001, "offset \(offset)")
            #expect(walker.standing <= screen.maxX - halfWindow + 0.001, "offset \(offset)")
            var previous = walker.standing
            for _ in 0..<(30 * 20) {
                walker.animator.advance(elapsedSeconds: LaneRedivisionTests.tick, mood: .ready)
                #expect(walker.standing >= screen.minX + halfWindow - 0.001)
                #expect(walker.standing <= screen.maxX - halfWindow + 0.001)
                #expect(abs(walker.standing - previous) <= PetAnimator.walkSpeedInPointsPerSecond * CGFloat(LaneRedivisionTests.tick) + 0.001)
                previous = walker.standing
            }
        }
    }

    @Test func aLonePetMeandersAcrossItsWholeLaneInsteadOfPacingEdgeToEdge() {
        let wideScreen = CGRect(x: 0, y: 0, width: 2560, height: 1415)
        let random = SeededRandom(seed: 106)
        let walker = TestWalker(home: wideScreen.midX, random: { random.next() })
        _ = LaneRedivision.apply(to: [walker], keepingStanding: [true], screenFrame: wideScreen)
        let wander = walker.animator.wanderHalfWidth
        let binCount = 20
        var visited = Set<Int>()
        var turnsInside = 0
        var turnsAtEnds = 0
        var lastDirection: CGFloat = 0
        var previous = walker.animator.horizontalOffsetFromHome
        for _ in 0..<(30 * 60 * 30) {
            walker.animator.advance(elapsedSeconds: LaneRedivisionTests.tick, mood: .ready)
            let offset = walker.animator.horizontalOffsetFromHome
            let moved = offset - previous
            if moved != 0 {
                let direction: CGFloat = moved > 0 ? 1 : -1
                if lastDirection != 0 && direction != lastDirection {
                    if abs(previous) >= wander - 1 { turnsAtEnds += 1 } else { turnsInside += 1 }
                }
                lastDirection = direction
            }
            visited.insert(min(binCount - 1, Int((offset + wander) / (2 * wander) * CGFloat(binCount))))
            previous = offset
        }
        #expect(visited.count == binCount)
        #expect(turnsInside > turnsAtEnds)
        #expect(turnsAtEnds > 0)
    }
}
