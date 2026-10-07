import CoreGraphics
import Foundation
import Testing
@testable import AgentPetCore
@testable import agent_pet

private final class Greeter: HighFiveParticipant, LaneWalker {
    let petKey: String
    var homeHorizontalCenter: CGFloat
    let animator: PetAnimator
    let spriteSideLength: CGFloat = 64
    var mood: PetMood = .ready
    var inFlight = false
    var body: GroundBody?
    let laneWidth: CGFloat = 72
    let windowWidth: CGFloat = 72
    var isInFlight: Bool { false }

    init(petKey: String, home: CGFloat) {
        self.petKey = petKey
        homeHorizontalCenter = home
        animator = PetAnimator(random: { 0.99 })
    }

    var x: CGFloat { homeHorizontalCenter + animator.horizontalOffsetFromHome }
}

private struct Tick {
    let leftX: CGFloat
    let rightX: CGFloat
    let leftFrame: Int?
    let rightFrame: Int?
    let leftAnimation: SpriteAnimationName
    let rightAnimation: SpriteAnimationName
    let phase: HighFiveDirector.Phase?
}

@Suite("neighbouring pets meet at their lane border and high five")
struct HighFiveTests {
    private static let tick = 1.0 / 30.0
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    private func pair(leftOffset: CGFloat = 290, rightOffset: CGFloat = -290, receiverStrolls: Bool = true) -> (Greeter, Greeter, CGFloat) {
        let left = Greeter(petKey: "left", home: 0)
        let right = Greeter(petKey: "right", home: 0)
        _ = LaneRedivision.apply(to: [left, right], keepingStanding: [false, false], screenFrame: screen)
        let gap = LaneLayout.minimumGroundGap(widestPet: 72, laneCount: 2, screenFrame: screen)
        for greeter in [left, right] {
            for _ in 0..<20 { greeter.animator.advance(elapsedSeconds: HighFiveTests.tick, mood: .ready) { _ in false } }
        }
        left.animator.stand(atHorizontalOffsetFromHome: leftOffset)
        left.animator.face(left: false)
        right.animator.stand(atHorizontalOffsetFromHome: rightOffset)
        right.animator.face(left: true)
        if receiverStrolls { right.animator.endMeeting(stepBackTo: -right.animator.wanderHalfWidth) }
        return (left, right, gap)
    }

    private func run(
        _ left: Greeter,
        _ right: Greeter,
        director: HighFiveDirector,
        gap: CGFloat,
        seconds: Double,
        startingAt start: Double = 0,
        isLevel: Bool = true,
        each: (Tick) -> Void = { _ in }
    ) {
        var now = start
        for _ in 0..<Int(seconds / HighFiveTests.tick) {
            director.tick(
                neighbours: [left, right].map { greeter in
                    HighFiveCandidate(
                        participant: greeter,
                        isFree: HighFiveDirector.isFree(animator: greeter.animator, mood: greeter.mood, inFlight: greeter.inFlight, body: greeter.body)
                    )
                },
                elapsedSeconds: HighFiveTests.tick,
                now: now
            ) { _, _, _ in isLevel }
            for (greeter, neighbour) in [(left, right), (right, left)] {
                greeter.animator.advance(elapsedSeconds: HighFiveTests.tick, mood: greeter.mood) { offset in
                    let pairGap = director.minimumGap(between: greeter.petKey, and: neighbour.petKey, normally: gap)
                    return LaneLayout.allowsStep(
                        from: greeter.x,
                        to: greeter.homeHorizontalCenter + offset,
                        neighbour: neighbour.x,
                        minimumGap: pairGap
                    )
                }
            }
            each(Tick(
                leftX: left.x,
                rightX: right.x,
                leftFrame: left.animator.highFiveFrame,
                rightFrame: right.animator.highFiveFrame,
                leftAnimation: left.animator.animationName,
                rightAnimation: right.animator.animationName,
                phase: director.phase
            ))
            now += HighFiveTests.tick
        }
    }

    @Test func facingNeighboursWalkToTheBorderMeetTouchAtOnceAndStepBack() {
        let (left, right, gap) = pair()
        let border = (left.homeHorizontalCenter + right.homeHorizontalCenter) / 2
        let spacing = HighFiveDirector.meetSpacing(left: left, right: right)
        let director = HighFiveDirector(random: { 0 })
        var ticks: [Tick] = []
        run(left, right, director: director, gap: gap, seconds: 8) { tick in ticks.append(tick) }

        for tick in ticks {
            #expect(tick.leftX < border)
            #expect(tick.rightX > border)
            #expect(tick.rightX - tick.leftX >= spacing - HighFiveDirector.spacingSlack - 0.001)
        }
        let meeting = ticks.filter { tick in tick.phase == .greeting || tick.phase == .contact }
        #expect(!meeting.isEmpty)
        for tick in meeting {
            #expect(abs(tick.leftX - (border - spacing / 2)) < 0.001)
            #expect(abs(tick.rightX - (border + spacing / 2)) < 0.001)
        }
        let contactTicks = ticks.indices.filter { index in
            ticks[index].leftFrame == HighFiveDirector.contactFrame || ticks[index].rightFrame == HighFiveDirector.contactFrame
        }
        #expect(!contactTicks.isEmpty)
        for index in contactTicks {
            #expect(ticks[index].leftFrame == HighFiveDirector.contactFrame)
            #expect(ticks[index].rightFrame == HighFiveDirector.contactFrame)
            #expect(ticks[index].leftAnimation == .highfive && ticks[index].rightAnimation == .highfive)
        }
        let firstLeftRaise = ticks.firstIndex { tick in tick.leftFrame != nil }
        let firstRightRaise = ticks.firstIndex { tick in tick.rightFrame != nil }
        let delay = Double((firstRightRaise ?? 0) - (firstLeftRaise ?? 0)) * HighFiveTests.tick
        #expect(abs(delay - HighFiveDirector.answerDelayInSeconds) <= HighFiveTests.tick + 0.001)
        let after = ticks.suffix(30)
        #expect(after.allSatisfy { tick in tick.phase == nil })
        #expect(after.allSatisfy { tick in tick.rightX - tick.leftX >= gap - 0.001 })
    }

    @Test func theReceiversPlanIsInterrupted() {
        let (left, right, gap) = pair()
        #expect(right.animator.strollDestination != nil)
        let director = HighFiveDirector(random: { 0 })
        run(left, right, director: director, gap: gap, seconds: HighFiveTests.tick)
        #expect(right.animator.strollDestination == nil)
        #expect(right.animator.meetingTarget != nil)
        #expect(left.animator.meetingTarget != nil)
    }

    @Test func aPairWaitsOutItsCooldown() {
        let (left, right, gap) = pair()
        let director = HighFiveDirector(random: { 0 })
        var starts = 0
        var previous: HighFiveDirector.Phase?
        let check = { (tick: Tick) in
            if previous == nil && tick.phase != nil { starts += 1 }
            previous = tick.phase
        }
        run(left, right, director: director, gap: gap, seconds: 10, each: check)
        #expect(starts == 1)
        left.animator.stand(atHorizontalOffsetFromHome: 290)
        left.animator.face(left: false)
        right.animator.stand(atHorizontalOffsetFromHome: -290)
        right.animator.face(left: true)
        run(left, right, director: director, gap: gap, seconds: 1, startingAt: 30, each: check)
        #expect(starts == 1)
        left.animator.stand(atHorizontalOffsetFromHome: 290)
        left.animator.face(left: false)
        right.animator.stand(atHorizontalOffsetFromHome: -290)
        right.animator.face(left: true)
        run(left, right, director: director, gap: gap, seconds: 1, startingAt: HighFiveDirector.pairCooldownInSeconds + 1, each: check)
        #expect(starts == 2)
    }

    @Test func petsFacingAwayOrFarApartNeverStart() {
        let (left, right, gap) = pair()
        left.animator.face(left: true)
        let director = HighFiveDirector(random: { 0 })
        var started = false
        run(left, right, director: director, gap: gap, seconds: HighFiveTests.tick) { tick in started = started || tick.phase != nil }
        #expect(!started)

        let (farLeft, farRight, farGap) = pair(leftOffset: 0, rightOffset: 0, receiverStrolls: false)
        run(farLeft, farRight, director: director, gap: farGap, seconds: HighFiveTests.tick) { tick in started = started || tick.phase != nil }
        #expect(!started)
    }

    @Test func noHighFiveForAPetThatIsBusyAwayFloatingInTheAirDivingOrOnAStep() {
        let cases: [(String, (Greeter, Greeter) -> Void, Bool)] = [
            ("waiting on its session", { _, right in right.mood = .needsInput }, true),
            ("blocked", { left, _ in left.mood = .blocked }, true),
            ("floating", { left, _ in left.inFlight = true }, true),
            ("airborne", { _, right in
                var body = GroundBody(height: 4)
                _ = body.allowsStep(toGround: 60)
                right.body = body
            }, true),
            ("diving", { left, _ in left.animator.requestDive() }, true),
            ("walking home", { left, _ in left.animator.moveHome(by: 900) }, true),
            ("on a Dock step", { _, _ in }, false)
        ]
        for (name, setUp, level) in cases {
            let (left, right, gap) = pair()
            setUp(left, right)
            let director = HighFiveDirector(random: { 0 })
            var started = false
            run(left, right, director: director, gap: gap, seconds: 0.2, isLevel: level) { tick in started = started || tick.phase != nil }
            #expect(!started, "\(name)")
        }
    }

    @Test func aPetThatStopsBeingFreeMidGreetingEndsItAndBothStepBack() {
        let (left, right, gap) = pair()
        let director = HighFiveDirector(random: { 0 })
        run(left, right, director: director, gap: gap, seconds: 0.5)
        #expect(director.phase != nil)
        right.mood = .needsInput
        run(left, right, director: director, gap: gap, seconds: HighFiveTests.tick)
        #expect(director.phase == nil)
        #expect(left.animator.meetingTarget == nil && right.animator.meetingTarget == nil)
        right.mood = .ready
        run(left, right, director: director, gap: gap, seconds: 6)
        #expect(right.x - left.x >= gap - 0.001)
    }

    @Test func theTriggerIsOccasionalAndSeeded() {
        var generator = SeededGenerator(seed: 109)
        let director = HighFiveDirector(random: { Double.random(in: 0..<1, using: &generator) })
        var startTicks: [Int] = []
        var tickIndex = 0
        var previous: HighFiveDirector.Phase?
        for _ in 0..<5 {
            let (left, right, gap) = pair()
            run(left, right, director: director, gap: gap, seconds: 1, startingAt: Double(tickIndex) * 100) { tick in
                if previous == nil && tick.phase != nil { startTicks.append(tickIndex) }
                previous = tick.phase
                tickIndex += 1
            }
            director.cancel()
            previous = nil
        }
        #expect(startTicks.count < 5)
    }
}
