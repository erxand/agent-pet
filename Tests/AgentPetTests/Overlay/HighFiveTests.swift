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

private func turn(_ greeter: Greeter, left facesLeft: Bool) {
    let offset = greeter.animator.horizontalOffsetFromHome
    greeter.animator.endMeeting(stepBackTo: offset + (facesLeft ? -20 : 20))
    greeter.animator.advance(elapsedSeconds: 1.0 / 30.0, mood: .ready)
    greeter.animator.stand(atHorizontalOffsetFromHome: offset)
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
        turn(left, left: false)
        right.animator.stand(atHorizontalOffsetFromHome: rightOffset)
        turn(right, left: true)
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
                    director.allowsStep(
                        of: greeter.petKey,
                        from: greeter.x,
                        to: greeter.homeHorizontalCenter + offset,
                        beside: neighbour.petKey,
                        at: neighbour.x,
                        normalGap: gap
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
            let secondFrames = greeting.ticks[second..<contact].map { tick in greeting.firstIsLeft ? tick.rightFrame : tick.leftFrame }
            #expect(secondFrames.contains(HighFiveDirector.raiseFrame) && secondFrames.contains(HighFiveDirector.reachFrame), "\(label)")
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
        turn(left, left: false)
        turn(right, left: true)
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

    @Test func aPetThatDivesMidGreetingSinksWithoutWalking() {
        let (left, right, gap) = pair()
        let director = HighFiveDirector(random: { 0 })
        run(left, right, director: director, gap: gap, seconds: 0.5)
        #expect(director.phase != nil)
        left.animator.requestDive()
        director.cancel()
        #expect(left.animator.meetingTarget == nil && left.animator.highFiveFrame == nil)
        #expect(left.animator.strollDestination == nil)
        #expect(left.animator.animationName == .dive)
        #expect(right.animator.strollDestination != nil)
    }

    @Test func bothLabelsFadeWhileThePairIsCloserThanTheGapIncludingTheStepBack() {
        let (left, right, gap) = pair()
        let director = HighFiveDirector(random: { 0 })
        var leftFade = 1.0
        var rightFade = 1.0
        var closeFor = 0
        var sawContactHidden = false
        var sawStepBackHidden = false
        let settleTicks = Int((HighFiveDirector.labelFadeInSeconds / HighFiveTests.tick).rounded(.up))
        run(left, right, director: director, gap: gap, seconds: 8) { tick in
            let hidden = HighFiveDirector.hiddenLabels([(key: "left", x: tick.leftX), (key: "right", x: tick.rightX)], normalGap: gap)
            leftFade = HighFiveDirector.chromeFade(leftFade, hidden: hidden.contains("left"), elapsedSeconds: HighFiveTests.tick)
            rightFade = HighFiveDirector.chromeFade(rightFade, hidden: hidden.contains("right"), elapsedSeconds: HighFiveTests.tick)
            closeFor = tick.rightX - tick.leftX < gap ? closeFor + 1 : 0
            if closeFor > settleTicks {
                #expect(leftFade == 0 && rightFade == 0)
                if tick.phase == .contact { sawContactHidden = true }
                if tick.phase == nil { sawStepBackHidden = true }
            }
        }
        #expect(sawContactHidden)
        #expect(sawStepBackHidden)
        #expect(leftFade == 1 && rightFade == 1)
    }

    @Test func aLaneReplanWhileWaitingOrTouchingDoesNotEndTheGreeting() {
        for phase in [HighFiveDirector.Phase.waiting, .contact] {
            let (left, right, gap) = pair()
            let director = HighFiveDirector(random: { 0 })
            var replanned = false
            var sawContactAfter = false
            run(left, right, director: director, gap: gap, seconds: 6) { tick in
                if !replanned && tick.phase == phase {
                    _ = LaneRedivision.apply(to: [left, right], keepingStanding: [true, true], screenFrame: screen)
                    #expect(!left.animator.isWalkingHome && !right.animator.isWalkingHome, "\(phase)")
                    replanned = true
                } else if replanned && tick.phase == .contact {
                    sawContactAfter = true
                }
            }
            #expect(replanned, "\(phase)")
            #expect(sawContactAfter, "\(phase)")
            #expect(!left.animator.isWalkingHome || abs(left.animator.horizontalOffsetFromHome) > left.animator.wanderHalfWidth)
        }
    }

    @Test func aGreetingSurvivesALaneReplanThatMovesNobodyButEndsWhenAThirdPetArrives() {
        let (left, right, gap) = pair()
        let director = HighFiveDirector(random: { 0 })
        run(left, right, director: director, gap: gap, seconds: 0.3)
        #expect(director.phase != nil)
        _ = LaneRedivision.apply(to: [left, right], keepingStanding: [true, true], screenFrame: screen)
        run(left, right, director: director, gap: gap, seconds: HighFiveTests.tick)
        #expect(director.phase != nil)
        let standing = [(key: "left", x: left.x), (key: "right", x: left.x + 10)]
        #expect(director.crowdedPairs(standing, normalGap: gap).isEmpty)
        #expect(HighFiveDirector(random: { 1 }).crowdedPairs(standing, normalGap: gap).count == 1)

        let wider = CGRect(x: 0, y: 0, width: 1460, height: 900)
        _ = LaneRedivision.apply(to: [left, right], keepingStanding: [true, true], screenFrame: wider)
        #expect(!left.animator.isWalkingHome && !right.animator.isWalkingHome)
        run(left, right, director: director, gap: gap, seconds: HighFiveTests.tick)
        #expect(director.phase == nil)

        run(left, right, director: director, gap: gap, seconds: 0.3)
        let third = Greeter(petKey: "third", home: 0)
        _ = LaneRedivision.apply(to: [left, right, third], keepingStanding: [true, true, false], screenFrame: screen)
        run(left, right, director: director, gap: gap, seconds: HighFiveTests.tick)
        #expect(director.phase == nil)
        #expect(left.animator.meetingTarget == nil && right.animator.meetingTarget == nil)
    }

    @Test func aDockEdgeBetweenAPetAndTheBorderMeansNoGreeting() {
        let edge: CGFloat = 700
        let dock = GroundProfile.dock(base: 4, segment: GroundSegment(minX: edge, maxX: 1400, top: 83))
        let flat = GroundProfile.flat(base: 4)
        let (left, right, gap) = pair()
        #expect(HighFiveDirector.levelPath(flat, for: left, from: left.x, to: 720))
        #expect(!HighFiveDirector.levelPath(dock, for: left, from: left.x, to: 720))
        #expect(HighFiveDirector.levelPath(dock, for: right, from: right.x, to: 760))
        #expect(dock.isLevel(over: 10...600))
        #expect(!dock.isLevel(over: 600...710))
        #expect(!dock.isLevel(over: 1390...1420))
        #expect(GroundProfile.dock(base: 4, segment: GroundSegment(minX: edge, maxX: 1400, top: -5)).isLevel(over: 600...710))
        let director = HighFiveDirector(random: { 0 })
        var started = false
        var now = 0.0
        for _ in 0..<10 {
            director.tick(
                neighbours: [left, right].map { greeter in HighFiveCandidate(participant: greeter, isFree: true) },
                elapsedSeconds: HighFiveTests.tick,
                now: now
            ) { participant, from, to in HighFiveDirector.levelPath(dock, for: participant, from: from, to: to) }
            started = started || director.phase != nil
            now += HighFiveTests.tick
        }
        #expect(!started)
        _ = gap
    }

    @Test func aboutOneEncounterInTenStartsAHighFive() {
        var generator = SeededGenerator(seed: 1090)
        var starts = 0
        let encounters = 400
        for index in 0..<encounters {
            let (left, right, _) = pair(receiverStrolls: false)
            let director = HighFiveDirector(random: { Double.random(in: 0..<1, using: &generator) })
            director.tick(
                neighbours: [left, right].map { greeter in HighFiveCandidate(participant: greeter, isFree: true) },
                elapsedSeconds: HighFiveTests.tick,
                now: Double(index)
            )
            if director.phase != nil { starts += 1 }
        }
        #expect(starts >= 25 && starts <= 55, "\(starts) of \(encounters)")
    }

    @Test func neighboursRestingExactlyAGapApartKeepTheirLabels() {
        let gap: CGFloat = 104
        let atTheGap = HighFiveDirector.hiddenLabels([(key: "a", x: 616), (key: "b", x: 616 + gap - 1e-9)], normalGap: gap)
        #expect(atTheGap.isEmpty)
        let meeting = HighFiveDirector.hiddenLabels([(key: "a", x: 616), (key: "b", x: 616 + 54)], normalGap: gap)
        #expect(meeting == ["a", "b"])
    }

    @Test func aMeetingTargetKeepsAMovedHomeFromStartingAWalkHome() {
        let (left, _, _) = pair()
        left.animator.beginMeeting(atOffset: left.animator.wanderHalfWidth + 40, facingLeft: false)
        left.animator.moveHome(by: 500)
        #expect(!left.animator.isWalkingHome)
        left.animator.limitWander(to: 10)
        #expect(!left.animator.isWalkingHome)
    }

    @Test func endingAMeetingOutsideTheRangeWalksHomeAndInsideDoesNot() {
        let (left, right, _) = pair()
        left.animator.stand(atHorizontalOffsetFromHome: left.animator.wanderHalfWidth + 30)
        left.animator.beginMeeting(atOffset: left.animator.horizontalOffsetFromHome, facingLeft: false)
        left.animator.endMeeting(stepBackTo: left.animator.wanderHalfWidth)
        #expect(left.animator.isWalkingHome)

        right.animator.stand(atHorizontalOffsetFromHome: -100)
        right.animator.walkHomeNow()
        right.animator.beginMeeting(atOffset: -100, facingLeft: true)
        right.animator.endMeeting(stepBackTo: -right.animator.wanderHalfWidth)
        #expect(!right.animator.isWalkingHome)
    }

    @Test func aPetWhoseSessionAsksMidGreetingWalksBackIntoItsRange() {
        let (left, right, gap) = pair()
        let director = HighFiveDirector(random: { 0 })
        run(left, right, director: director, gap: gap, seconds: 6) { tick in
            if tick.phase == .contact { right.mood = .needsInput }
        }
        #expect(director.phase == nil)
        #expect(abs(right.animator.horizontalOffsetFromHome) <= right.animator.wanderHalfWidth + 0.001)
        #expect(!right.animator.isWalkingHome)
    }

    @Test func aReplanThatShiftsAHomeWhileWaitingEndsTheGreetingCleanly() {
        let (left, right, gap) = pair()
        let director = HighFiveDirector(random: { 0 })
        var shifted = false
        run(left, right, director: director, gap: gap, seconds: 8) { tick in
            if !shifted && tick.phase == .waiting {
                _ = LaneRedivision.apply(to: [left, right], keepingStanding: [true, true], screenFrame: CGRect(x: 0, y: 0, width: 1500, height: 900))
                #expect(!left.animator.isWalkingHome && !right.animator.isWalkingHome)
                shifted = true
            }
        }
        #expect(shifted)
        #expect(director.phase == nil)
        #expect(right.x - left.x >= gap - 0.001)
        #expect(abs(left.animator.horizontalOffsetFromHome) <= left.animator.wanderHalfWidth + 0.001)
        #expect(abs(right.animator.horizontalOffsetFromHome) <= right.animator.wanderHalfWidth + 0.001)
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
        #expect(mean >= 1 && mean <= 4, "\(counts)")
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
        turn(left, left: false)
        right.animator.stand(atHorizontalOffsetFromHome: -290)
        turn(right, left: true)
        run(left, right, director: director, gap: gap, seconds: 1, startingAt: 30, each: check)
        #expect(starts == 1)
        left.animator.stand(atHorizontalOffsetFromHome: 290)
        turn(left, left: false)
        right.animator.stand(atHorizontalOffsetFromHome: -290)
        turn(right, left: false)
        run(left, right, director: director, gap: gap, seconds: HighFiveTests.tick, startingAt: HighFiveDirector.pairCooldownInSeconds, each: check)
        left.animator.stand(atHorizontalOffsetFromHome: 290)
        turn(left, left: false)
        right.animator.stand(atHorizontalOffsetFromHome: -290)
        turn(right, left: true)
        run(left, right, director: director, gap: gap, seconds: 1, startingAt: HighFiveDirector.pairCooldownInSeconds + 1, each: check)
        #expect(starts == 2)
    }

    @Test func petsFacingAwayOrFarApartNeverStart() {
        let (left, right, gap) = pair()
        turn(left, left: true)
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
            ("walking home", { left, _ in left.animator.limitWander(to: 200) }, true),
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
}
