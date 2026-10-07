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
    static let triggerRatePerSecond: Double = 0.2
    static let pairCooldownInSeconds: TimeInterval = 60
    static let answerDelayInSeconds: Double = 0.4
    static let raiseFrameInSeconds: Double = 0.15
    static let contactHoldInSeconds: Double = 0.4
    static let approachTimeoutInSeconds: Double = 10
    static let meetSpacingFraction: CGFloat = 0.85
    static let raiseFrame = 0
    static let reachFrame = 1
    static let contactFrame = 2
    static let spacingSlack: CGFloat = 0.5

    enum Phase: Equatable {
        case approaching
        case greeting
        case contact
    }

    private struct Session {
        let left: HighFiveParticipant
        let right: HighFiveParticipant
        let initiatorIsLeft: Bool
        var phase: Phase
        var phaseSeconds: Double
    }

    private let random: () -> Double
    private var session: Session?
    private var lastGreetedAt: [String: TimeInterval] = [:]

    init(random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.random = random
    }

    var phase: Phase? { session?.phase }

    func isGreeting(_ petKey: String) -> Bool {
        guard let session else { return false }
        return session.left.petKey == petKey || session.right.petKey == petKey
    }

    func isMeetingPair(_ first: String, _ second: String) -> Bool {
        guard let session else { return false }
        let keys = Set([session.left.petKey, session.right.petKey])
        return keys == Set([first, second])
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

    func cancel() {
        guard let current = session else { return }
        finish(current)
    }

    func minimumGap(between first: String, and second: String, normally gap: CGFloat) -> CGFloat {
        guard let session, isMeetingPair(first, second) else { return gap }
        return min(gap, HighFiveDirector.meetSpacing(left: session.left, right: session.right) - HighFiveDirector.spacingSlack)
    }

    func tick(
        neighbours: [HighFiveCandidate],
        elapsedSeconds: Double,
        now: TimeInterval,
        isLevel: (HighFiveParticipant, CGFloat, CGFloat) -> Bool = { _, _, _ in true }
    ) {
        if var current = session {
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
            if let last = lastGreetedAt[pair], now - last < HighFiveDirector.pairCooldownInSeconds { continue }
            guard random() < HighFiveDirector.triggerRatePerSecond * elapsedSeconds else { continue }
            start(left: leftPet, right: rightPet, initiatorIsLeft: random() < 0.5, now: now)
            return
        }
    }

    private func start(left: HighFiveParticipant, right: HighFiveParticipant, initiatorIsLeft: Bool, now: TimeInterval) {
        let border = (left.homeHorizontalCenter + right.homeHorizontalCenter) / 2
        let halfSpacing = HighFiveDirector.meetSpacing(left: left, right: right) / 2
        left.animator.beginMeeting(atOffset: border - halfSpacing - left.homeHorizontalCenter, facingLeft: false)
        right.animator.beginMeeting(atOffset: border + halfSpacing - right.homeHorizontalCenter, facingLeft: true)
        lastGreetedAt[HighFiveDirector.pairKey(left.petKey, right.petKey)] = now
        session = Session(left: left, right: right, initiatorIsLeft: initiatorIsLeft, phase: .approaching, phaseSeconds: 0)
    }

    private func advance(_ current: inout Session, elapsedSeconds: Double) {
        current.phaseSeconds += elapsedSeconds
        switch current.phase {
        case .approaching:
            if current.left.animator.hasReachedMeeting && current.right.animator.hasReachedMeeting {
                current.phase = .greeting
                current.phaseSeconds = 0
            } else if current.phaseSeconds >= HighFiveDirector.approachTimeoutInSeconds {
                finish(current)
                return
            }
        case .greeting:
            let initiator = current.initiatorIsLeft ? current.left : current.right
            let receiver = current.initiatorIsLeft ? current.right : current.left
            initiator.animator.showHighFive(frame: raisedFrame(after: current.phaseSeconds))
            let answeredFor = current.phaseSeconds - HighFiveDirector.answerDelayInSeconds
            if answeredFor >= 0 {
                receiver.animator.showHighFive(frame: raisedFrame(after: answeredFor))
            }
            if answeredFor >= HighFiveDirector.raiseFrameInSeconds {
                current.phase = .contact
                current.phaseSeconds = 0
                current.left.animator.showHighFive(frame: HighFiveDirector.contactFrame)
                current.right.animator.showHighFive(frame: HighFiveDirector.contactFrame)
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
