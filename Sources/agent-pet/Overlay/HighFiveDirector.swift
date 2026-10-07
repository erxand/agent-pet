import AgentPetCore
import AppKit

protocol HighFiveParticipant: AnyObject {
    var petKey: String { get }
    var homeHorizontalCenter: CGFloat { get }
    var animator: PetAnimator { get }
    var spriteSideLength: CGFloat { get }
}

struct HighFiveCandidate {
    let participant: HighFiveParticipant
    let isFree: Bool
}

final class HighFiveDirector {
    static let greetingDistance: CGFloat = 320
    static let chancePerEncounter: Double = 0.1
    static let pairCooldownInSeconds: TimeInterval = 600
    static let arrivalStaggerInSeconds: Double = 0.6
    static let raiseFrameInSeconds: Double = 0.15
    static let contactHoldInSeconds: Double = 0.4
    static let approachTimeoutInSeconds: Double = 10
    static let meetSpacingFraction: CGFloat = 0.85
    static let spacingSlack: CGFloat = 0.5
    static let raiseFrame = 0
    static let reachFrame = 1
    static let contactFrame = 2
    static let labelFadeInSeconds: Double = 0.15

    enum Phase: Equatable {
        case approaching
        case waiting
        case contact
    }

    private struct Session {
        let left: HighFiveParticipant
        let right: HighFiveParticipant
        let first: HighFiveParticipant
        let second: HighFiveParticipant
        let secondTarget: CGFloat
        let secondFacesLeft: Bool
        let homes: [CGFloat]
        let wanderHalfWidths: [CGFloat]
        var secondSetsOutIn: Double
        var firstRaisedFor: Double?
        var secondRaisedFor: Double?
        var phase: Phase
        var phaseSeconds: Double
    }

    private let random: () -> Double
    private var session: Session?
    private var lastGreetedAt: [String: TimeInterval] = [:]
    private var facingPairs: Set<String> = []

    init(random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.random = random
    }

    var phase: Phase? { session?.phase }
    var firstArriverKey: String? { session?.first.petKey }

    func isGreeting(_ petKey: String) -> Bool {
        guard let session else { return false }
        return session.left.petKey == petKey || session.right.petKey == petKey
    }

    func isMeetingPair(_ first: String, _ second: String) -> Bool {
        guard let session else { return false }
        return Set([session.left.petKey, session.right.petKey]) == Set([first, second])
    }

    static func isFree(animator: PetAnimator, mood: PetMood, inFlight: Bool, body: GroundBody?) -> Bool {
        guard !inFlight, animator.isGrounded, !animator.isWalkingHome, mood == .ready else { return false }
        if let body, body.phase != .standing { return false }
        return true
    }

    static func pairKey(_ first: String, _ second: String) -> String {
        [first, second].sorted().joined(separator: "|")
    }

    static func meetSpacing(left: HighFiveParticipant, right: HighFiveParticipant) -> CGFloat {
        (left.spriteSideLength + right.spriteSideLength) / 2 * meetSpacingFraction
    }

    func minimumGap(between first: String, and second: String, normally gap: CGFloat) -> CGFloat {
        guard let session, isMeetingPair(first, second) else { return gap }
        return min(gap, HighFiveDirector.meetSpacing(left: session.left, right: session.right) - HighFiveDirector.spacingSlack)
    }

    static func hiddenLabels(_ standing: [(key: String, x: CGFloat)], normalGap: CGFloat) -> Set<String> {
        var hidden: Set<String> = []
        for (left, right) in zip(standing, standing.dropFirst()) where right.x - left.x < normalGap {
            hidden.insert(left.key)
            hidden.insert(right.key)
        }
        return hidden
    }

    static func chromeFade(_ current: Double, hidden: Bool, elapsedSeconds: Double) -> Double {
        let step = elapsedSeconds / labelFadeInSeconds
        return hidden ? max(0, current - step) : min(1, current + step)
    }

    func allowsStep(of mover: String, from current: CGFloat, to next: CGFloat, beside neighbour: String, at neighbourX: CGFloat, normalGap: CGFloat) -> Bool {
        LaneLayout.allowsStep(
            from: current,
            to: next,
            neighbour: neighbourX,
            minimumGap: minimumGap(between: mover, and: neighbour, normally: normalGap)
        )
    }

    func crowdedPairs(_ standing: [(key: String, x: CGFloat)], normalGap: CGFloat) -> [(Int, Int)] {
        zip(standing.indices, standing.indices.dropFirst()).filter { left, right in
            standing[right].x - standing[left].x < normalGap && !isMeetingPair(standing[left].key, standing[right].key)
        }
    }

    static func levelPath(_ profile: GroundProfile, for participant: HighFiveParticipant, from: CGFloat, to: CGFloat) -> Bool {
        let halfBody = participant.spriteSideLength * LaneLayout.bodyWidthFraction / 2
        return profile.isLevel(over: (min(from, to) - halfBody)...(max(from, to) + halfBody))
    }

    func cancel() {
        guard let current = session else { return }
        finish(current)
    }

    func tick(
        neighbours: [HighFiveCandidate],
        elapsedSeconds: Double,
        now: TimeInterval,
        isLevel: (HighFiveParticipant, CGFloat, CGFloat) -> Bool = { _, _, _ in true }
    ) {
        lastGreetedAt = lastGreetedAt.filter { _, greetedAt in now - greetedAt < HighFiveDirector.pairCooldownInSeconds }
        if var current = session {
            guard [current.left, current.right].map({ participant in participant.homeHorizontalCenter }) == current.homes,
                  [current.left, current.right].map({ participant in participant.animator.wanderHalfWidth }) == current.wanderHalfWidths
            else {
                finish(current)
                return
            }
            let free = Dictionary(neighbours.map { candidate in (candidate.participant.petKey, candidate.isFree) }, uniquingKeysWith: { first, _ in first })
            let keys = neighbours.map { candidate in candidate.participant.petKey }
            let stillNeighbours = zip(keys, keys.dropFirst()).contains { left, right in
                left == current.left.petKey && right == current.right.petKey
            }
            guard stillNeighbours, free[current.left.petKey] == true, free[current.right.petKey] == true else {
                finish(current)
                return
            }
            advance(&current, elapsedSeconds: elapsedSeconds)
            return
        }
        var facingNow: Set<String> = []
        var encounter: (HighFiveParticipant, HighFiveParticipant)?
        for (left, right) in zip(neighbours, neighbours.dropFirst()) {
            guard left.isFree, right.isFree else { continue }
            let leftPet = left.participant
            let rightPet = right.participant
            guard !leftPet.animator.facingLeft, rightPet.animator.facingLeft else { continue }
            let leftX = leftPet.homeHorizontalCenter + leftPet.animator.horizontalOffsetFromHome
            let rightX = rightPet.homeHorizontalCenter + rightPet.animator.horizontalOffsetFromHome
            guard rightX > leftX, rightX - leftX <= HighFiveDirector.greetingDistance else { continue }
            let border = (leftPet.homeHorizontalCenter + rightPet.homeHorizontalCenter) / 2
            guard isLevel(leftPet, leftX, border), isLevel(rightPet, rightX, border) else { continue }
            let pair = HighFiveDirector.pairKey(leftPet.petKey, rightPet.petKey)
            facingNow.insert(pair)
            guard !facingPairs.contains(pair), encounter == nil else { continue }
            if let last = lastGreetedAt[pair], now - last < HighFiveDirector.pairCooldownInSeconds { continue }
            if random() < HighFiveDirector.chancePerEncounter { encounter = (leftPet, rightPet) }
        }
        facingPairs = facingNow
        if let (left, right) = encounter { start(left: left, right: right, now: now) }
    }

    private func start(left: HighFiveParticipant, right: HighFiveParticipant, now: TimeInterval) {
        let border = (left.homeHorizontalCenter + right.homeHorizontalCenter) / 2
        let halfSpacing = HighFiveDirector.meetSpacing(left: left, right: right) / 2
        let leftTarget = border - halfSpacing - left.homeHorizontalCenter
        let rightTarget = border + halfSpacing - right.homeHorizontalCenter
        let leftDistance = abs(leftTarget - left.animator.horizontalOffsetFromHome)
        let rightDistance = abs(rightTarget - right.animator.horizontalOffsetFromHome)
        let leftFirst = leftDistance == rightDistance ? random() < 0.5 : leftDistance < rightDistance
        let first = leftFirst ? left : right
        let second = leftFirst ? right : left
        let firstDistance = leftFirst ? leftDistance : rightDistance
        let secondDistance = leftFirst ? rightDistance : leftDistance
        let naturalLead = Double((secondDistance - firstDistance) / PetAnimator.walkSpeedInPointsPerSecond)
        let secondTarget = leftFirst ? rightTarget : leftTarget
        let secondSetsOutIn = max(0, HighFiveDirector.arrivalStaggerInSeconds - naturalLead)
        first.animator.beginMeeting(atOffset: leftFirst ? leftTarget : rightTarget, facingLeft: !leftFirst)
        second.animator.beginMeeting(
            atOffset: secondSetsOutIn > 0 ? second.animator.horizontalOffsetFromHome : secondTarget,
            facingLeft: leftFirst
        )
        lastGreetedAt[HighFiveDirector.pairKey(left.petKey, right.petKey)] = now
        session = Session(
            left: left,
            right: right,
            first: first,
            second: second,
            secondTarget: secondTarget,
            secondFacesLeft: leftFirst,
            homes: [left.homeHorizontalCenter, right.homeHorizontalCenter],
            wanderHalfWidths: [left.animator.wanderHalfWidth, right.animator.wanderHalfWidth],
            secondSetsOutIn: secondSetsOutIn,
            firstRaisedFor: nil,
            secondRaisedFor: nil,
            phase: .approaching,
            phaseSeconds: 0
        )
    }

    private func advance(_ current: inout Session, elapsedSeconds: Double) {
        current.phaseSeconds += elapsedSeconds
        if current.secondSetsOutIn > 0 {
            current.secondSetsOutIn -= elapsedSeconds
            if current.secondSetsOutIn <= 0 {
                current.second.animator.beginMeeting(atOffset: current.secondTarget, facingLeft: current.secondFacesLeft)
            }
        }
        switch current.phase {
        case .approaching, .waiting:
            if current.phaseSeconds >= HighFiveDirector.approachTimeoutInSeconds {
                finish(current)
                return
            }
            if let raised = current.firstRaisedFor {
                current.firstRaisedFor = raised + elapsedSeconds
            } else if current.first.animator.hasReachedMeeting {
                current.firstRaisedFor = 0
                current.phase = .waiting
            }
            if let raised = current.firstRaisedFor {
                current.first.animator.showHighFive(frame: raisedFrame(after: raised))
            }
            let secondArrived = current.secondSetsOutIn <= 0
                && current.second.animator.hasReachedMeeting
                && current.firstRaisedFor != nil
            if let raised = current.secondRaisedFor {
                current.secondRaisedFor = raised + elapsedSeconds
            } else if secondArrived {
                current.secondRaisedFor = 0
            }
            if let raised = current.secondRaisedFor {
                if raised >= 2 * HighFiveDirector.raiseFrameInSeconds {
                    current.phase = .contact
                    current.phaseSeconds = 0
                    current.left.animator.showHighFive(frame: HighFiveDirector.contactFrame)
                    current.right.animator.showHighFive(frame: HighFiveDirector.contactFrame)
                } else {
                    current.second.animator.showHighFive(frame: raisedFrame(after: raised))
                }
            }
        case .contact:
            if current.phaseSeconds >= HighFiveDirector.contactHoldInSeconds {
                finish(current)
                return
            }
        }
        session = current
    }

    private func raisedFrame(after seconds: Double) -> Int {
        seconds < HighFiveDirector.raiseFrameInSeconds ? HighFiveDirector.raiseFrame : HighFiveDirector.reachFrame
    }

    private func finish(_ current: Session) {
        current.left.animator.endMeeting(stepBackTo: current.left.animator.wanderHalfWidth)
        current.right.animator.endMeeting(stepBackTo: -current.right.animator.wanderHalfWidth)
        session = nil
    }
}
