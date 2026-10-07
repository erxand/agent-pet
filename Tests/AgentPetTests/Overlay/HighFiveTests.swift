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

    init(petKey: String, home: CGFloat, random: @escaping () -> Double = { 0.99 }) {
        self.petKey = petKey
        homeHorizontalCenter = home
        animator = PetAnimator(random: random)
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

    private struct Arrivals {
        var first: Int?
        var second: Int?
        var firstRaise: Int?
        var contact: Int?
    }

    private func greet(leftOffset: CGFloat, rightOffset: CGFloat, coin: Double) -> (ticks: [Tick], arrivals: Arrivals, firstIsLeft: Bool, border: CGFloat, spacing: CGFloat, gap: CGFloat) {
        let (left, right, gap) = pair(leftOffset: leftOffset, rightOffset: rightOffset)
        let border = (left.homeHorizontalCenter + right.homeHorizontalCenter) / 2
        let spacing = HighFiveDirector.meetSpacing(left: left, right: right)
        var draws = [0, coin].makeIterator()
        let director = HighFiveDirector(random: { draws.next() ?? coin })
        var ticks: [Tick] = []
        var arrivals = Arrivals()
        var firstIsLeft = true
        var index = 0
        run(left, right, director: director, gap: gap, seconds: 10) { tick in
            if index == 0 { firstIsLeft = director.firstArriverKey == left.petKey }
            let leftThere = abs(tick.leftX - (border - spacing / 2)) < 0.001
            let rightThere = abs(tick.rightX - (border + spacing / 2)) < 0.001
            let firstThere = firstIsLeft ? leftThere : rightThere
            let secondThere = firstIsLeft ? rightThere : leftThere
            if arrivals.first == nil && firstThere { arrivals.first = index }
            if arrivals.second == nil && secondThere { arrivals.second = index }
            let firstFrame = firstIsLeft ? tick.leftFrame : tick.rightFrame
            if arrivals.firstRaise == nil && firstFrame != nil { arrivals.firstRaise = index }
            if arrivals.contact == nil && tick.phase == .contact { arrivals.contact = index }
            ticks.append(tick)
            index += 1
        }
        return (ticks, arrivals, firstIsLeft, border, spacing, gap)
    }

    @Test func theFirstToArriveRaisesAndWaitsAndBothTouchOnTheSameTick() {
        let layouts: [(CGFloat, CGFloat, Double)] = [(290, -290, 0), (290, -290, 0.9), (200, -300, 0), (310, -100, 0), (250, -250, 0.4)]
        let staggerTicks = Int(HighFiveDirector.arrivalStaggerInSeconds / HighFiveTests.tick)
        for (leftOffset, rightOffset, coin) in layouts {
            let label = "\(leftOffset) \(rightOffset) \(coin)"
            let greeting = greet(leftOffset: leftOffset, rightOffset: rightOffset, coin: coin)
            guard let first = greeting.arrivals.first, let second = greeting.arrivals.second,
                  let raise = greeting.arrivals.firstRaise, let contact = greeting.arrivals.contact else {
                Issue.record("\(label): \(greeting.arrivals)")
                continue
            }
            #expect(second - first >= staggerTicks - 1, "\(label): arrivals \(first) and \(second)")
            #expect(raise <= first + 1 && raise < second, "\(label)")
            for index in (raise + Int(HighFiveDirector.raiseFrameInSeconds / HighFiveTests.tick) + 1)..<contact {
                let frame = greeting.firstIsLeft ? greeting.ticks[index].leftFrame : greeting.ticks[index].rightFrame
                #expect(frame == HighFiveDirector.reachFrame, "\(label) tick \(index)")
            }
            for index in 0..<second {
                let frame = greeting.firstIsLeft ? greeting.ticks[index].rightFrame : greeting.ticks[index].leftFrame
                #expect(frame == nil, "\(label) tick \(index)")
            }
            for tick in greeting.ticks where tick.leftFrame == HighFiveDirector.contactFrame || tick.rightFrame == HighFiveDirector.contactFrame {
                #expect(tick.leftFrame == HighFiveDirector.contactFrame && tick.rightFrame == HighFiveDirector.contactFrame, "\(label)")
                #expect(tick.leftAnimation == .highfive && tick.rightAnimation == .highfive)
            }
            for tick in greeting.ticks {
                #expect(tick.leftX < greeting.border && tick.rightX > greeting.border)
                #expect(tick.rightX - tick.leftX >= greeting.spacing - HighFiveDirector.spacingSlack - 0.001)
            }
            let after = greeting.ticks.suffix(30)
            #expect(after.allSatisfy { tick in tick.phase == nil }, "\(label)")
            #expect(after.allSatisfy { tick in tick.rightX - tick.leftX >= greeting.gap - 0.001 }, "\(label)")
        }
    }

    @Test func aPairThatKeepsFacingEachOtherIsAskedOnlyOnce() {
        let (left, right, gap) = pair(receiverStrolls: false)
        left.homeHorizontalCenter = 660
        right.homeHorizontalCenter = 780
        for greeter in [left, right] {
            greeter.animator.limitWander(to: 0)
            greeter.animator.stand(atHorizontalOffsetFromHome: 0)
        }
        left.animator.face(left: false)
        right.animator.face(left: true)
        var draws = 0
        let director = HighFiveDirector(random: {
            draws += 1
            return draws == 1 ? HighFiveDirector.chancePerEncounter : 0
        })
        var started = false
        run(left, right, director: director, gap: gap, seconds: 60) { tick in started = started || tick.phase != nil }
        #expect(!started)
        #expect(draws == 1)
        #expect(!left.animator.facingLeft && right.animator.facingLeft)
    }

    @Test func overAnHourOfWanderingAPairHighFivesOnlyNowAndThen() {
        var counts: [Int] = []
        for seed in UInt64(1)...6 {
            var generator = SeededGenerator(seed: seed)
            let draw = { Double.random(in: 0..<1, using: &generator) }
            let left = Greeter(petKey: "left", home: 0, random: draw)
            let right = Greeter(petKey: "right", home: 0, random: draw)
            _ = LaneRedivision.apply(to: [left, right], keepingStanding: [false, false], screenFrame: screen)
            let gap = LaneLayout.minimumGroundGap(widestPet: 72, laneCount: 2, screenFrame: screen)
            let director = HighFiveDirector(random: draw)
            var starts = 0
            var previous: HighFiveDirector.Phase?
            run(left, right, director: director, gap: gap, seconds: 3600) { tick in
                if previous == nil && tick.phase != nil { starts += 1 }
                previous = tick.phase
            }
            counts.append(starts)
        }
        let mean = Double(counts.reduce(0, +)) / Double(counts.count)
        #expect(counts.allSatisfy { count in count <= Int(3600 / HighFiveDirector.pairCooldownInSeconds) + 1 })
        #expect(mean >= 0.5 && mean <= 6)
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
        right.animator.face(left: false)
        run(left, right, director: director, gap: gap, seconds: HighFiveTests.tick, startingAt: HighFiveDirector.pairCooldownInSeconds, each: check)
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
