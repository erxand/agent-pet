import AgentPetCore
import AppKit

enum PetGroundPhase {
    case emerging
    case grounded
    case diving
    case submerged
}

final class PetAnimator {
    private static let framesPerSecond: Double = 8
    static let walkSpeedInPointsPerSecond: CGFloat = 40
    private static let emergeDurationInSeconds: Double = 0.45
    private static let emergeChromeFadeInDurationInSeconds: Double = 0.15
    private static let diveChromeFadeOutDurationInSeconds: Double = 0.1
    private static let diveDescentDurationInSeconds: Double = 0.35
    static let maximumGroundStepInSeconds: Double = 1.0 / 15.0
    private static let minimumPauseInSeconds: Double = 1
    private static let maximumPauseInSeconds: Double = 3
    private static let minimumWalkInSeconds: Double = 1.5
    private static let maximumWalkInSeconds: Double = 5
    private static let waveDurationInSeconds: Double = 1.5
    private static let waveProbability: Double = 0.35
    static let meanderProbability: Double = 0.35
    private static let fullyUnderground: Double = 1
    private static let fullyAboveGround: Double = 0
    private static let opaqueChrome: Double = 1
    private static let transparentChrome: Double = 0

    private(set) var animationName: SpriteAnimationName = .emerge
    private(set) var frameTick = 0
    private(set) var facingLeft = false
    private(set) var horizontalOffsetFromHome: CGFloat = 0
    private(set) var bubbleVerticalOffset: CGFloat = 0
    private(set) var groundPhase: PetGroundPhase = .emerging
    private(set) var groundOffsetFraction: Double = PetAnimator.fullyUnderground
    private(set) var chromeOpacity: Double = PetAnimator.transparentChrome
    private(set) var groundAnimationProgress: Double = 0
    private(set) var isWalkingHome = false
    private(set) var wanderHalfWidth: CGFloat = LaneLayout.initialWanderHalfWidth

    private var frameClockInSeconds: Double = 0
    private var remainingActivityInSeconds: Double = 0
    private var bubblePhaseInSeconds: Double = 0
    private var phaseElapsedSeconds: Double = 0
    private var walkDirection: CGFloat = 1
    private(set) var walkWasBlocked = false
    private var diveStartGroundOffsetFraction: Double = PetAnimator.fullyAboveGround
    private var diveStartChromeOpacity: Double = PetAnimator.opaqueChrome

    private let random: () -> Double

    init(random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.random = random
        startEmerging(fromGroundOffsetFraction: PetAnimator.fullyUnderground)
    }

    private func randomValue(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * random()
    }

    var isSubmerged: Bool {
        switch groundPhase {
        case .submerged: return true
        case .emerging, .grounded, .diving: return false
        }
    }

    var isDiving: Bool {
        switch groundPhase {
        case .diving: return true
        case .emerging, .grounded, .submerged: return false
        }
    }

    var playsGroundAnimationOnce: Bool {
        switch groundPhase {
        case .emerging, .diving: return true
        case .grounded, .submerged: return false
        }
    }

    func requestEmerge() {
        switch groundPhase {
        case .emerging, .grounded:
            return
        case .diving, .submerged:
            startEmerging(fromGroundOffsetFraction: groundOffsetFraction)
        }
    }

    func hideChrome() {
        chromeOpacity = PetAnimator.transparentChrome
    }

    func requestDive() {
        switch groundPhase {
        case .diving, .submerged:
            return
        case .emerging, .grounded:
            startDiving(fromGroundOffsetFraction: groundOffsetFraction)
        }
    }

    func advance(
        elapsedSeconds unclampedElapsedSeconds: Double,
        mood: PetMood,
        canMoveTo: (CGFloat) -> Bool = { _ in true }
    ) {
        let elapsedSeconds = playsGroundAnimationOnce
            ? min(unclampedElapsedSeconds, PetAnimator.maximumGroundStepInSeconds)
            : unclampedElapsedSeconds
        advanceFrameClock(elapsedSeconds: elapsedSeconds)
        advanceBubbleBob(elapsedSeconds: elapsedSeconds)

        switch groundPhase {
        case .emerging:
            advanceEmerging(elapsedSeconds: elapsedSeconds)
        case .grounded:
            if isWalkingHome {
                walkHome(elapsedSeconds: elapsedSeconds, mood: mood, canMoveTo: canMoveTo)
            } else {
                advanceMoodBehavior(elapsedSeconds: elapsedSeconds, mood: mood, canMoveTo: canMoveTo)
            }
        case .diving:
            advanceDiving(elapsedSeconds: elapsedSeconds)
        case .submerged:
            return
        }
    }

    func advanceInSpace(elapsedSeconds: Double) {
        advanceFrameClock(elapsedSeconds: elapsedSeconds)
        advanceBubbleBob(elapsedSeconds: elapsedSeconds)
    }

    func resumeGrounded(horizontalOffsetFromHome offset: CGFloat) {
        horizontalOffsetFromHome = offset
        isWalkingHome = abs(offset) > 0
        beginWalking()
    }

    func limitWander(to halfWidth: CGFloat) {
        wanderHalfWidth = max(0, halfWidth)
        if abs(horizontalOffsetFromHome) > wanderHalfWidth { isWalkingHome = true }
    }

    func forgetBlockedWalk() {
        walkWasBlocked = false
    }

    func walkHomeNow() {
        guard horizontalOffsetFromHome != 0 else { return }
        isWalkingHome = true
    }

    func stand(atHorizontalOffsetFromHome offset: CGFloat) {
        horizontalOffsetFromHome = offset
        isWalkingHome = abs(offset) > wanderHalfWidth
    }

    func moveHome(by shift: CGFloat) {
        guard shift != 0 else { return }
        horizontalOffsetFromHome -= shift
        if abs(horizontalOffsetFromHome) > wanderHalfWidth {
            isWalkingHome = true
        }
    }

    var isGrounded: Bool {
        switch groundPhase {
        case .grounded: return true
        case .emerging, .diving, .submerged: return false
        }
    }

    private func startEmerging(fromGroundOffsetFraction startingFraction: Double) {
        groundPhase = .emerging
        groundOffsetFraction = PetAnimator.clampedUnitValue(startingFraction)
        phaseElapsedSeconds = PetAnimator.emergeElapsedSeconds(
            forGroundOffsetFraction: groundOffsetFraction
        )
        chromeOpacity = PetAnimator.emergeChromeOpacity(phaseElapsedSeconds: phaseElapsedSeconds)
        groundAnimationProgress = phaseElapsedSeconds / PetAnimator.emergeDurationInSeconds
        beginGroundAnimation(named: .emerge)
    }

    private func startDiving(fromGroundOffsetFraction startingFraction: Double) {
        groundPhase = .diving
        diveStartGroundOffsetFraction = PetAnimator.clampedUnitValue(startingFraction)
        diveStartChromeOpacity = PetAnimator.clampedUnitValue(chromeOpacity)
        groundOffsetFraction = diveStartGroundOffsetFraction
        phaseElapsedSeconds = 0
        groundAnimationProgress = 0
        beginGroundAnimation(named: .dive)
        guard diveStartGroundOffsetFraction >= PetAnimator.fullyUnderground else { return }
        submerge()
    }

    private func submerge() {
        groundPhase = .submerged
        groundOffsetFraction = PetAnimator.fullyUnderground
        chromeOpacity = PetAnimator.transparentChrome
        groundAnimationProgress = 1
    }

    private func beginGroundAnimation(named groundAnimationName: SpriteAnimationName) {
        animationName = groundAnimationName
        frameTick = 0
        frameClockInSeconds = 0
        remainingActivityInSeconds = 0
    }

    private func advanceEmerging(elapsedSeconds: Double) {
        phaseElapsedSeconds += elapsedSeconds
        let progress = min(1, phaseElapsedSeconds / PetAnimator.emergeDurationInSeconds)
        groundAnimationProgress = progress
        groundOffsetFraction = PetAnimator.easeOutRemainingDistance(progress: progress)
        chromeOpacity = PetAnimator.emergeChromeOpacity(phaseElapsedSeconds: phaseElapsedSeconds)
        guard progress >= 1 else { return }
        groundPhase = .grounded
        groundOffsetFraction = PetAnimator.fullyAboveGround
        chromeOpacity = PetAnimator.opaqueChrome
        groundAnimationProgress = 0
        beginWalking()
    }

    private func advanceDiving(elapsedSeconds: Double) {
        phaseElapsedSeconds += elapsedSeconds
        let fadeOutSeconds = diveStartChromeOpacity * PetAnimator.diveChromeFadeOutDurationInSeconds
        chromeOpacity = max(
            PetAnimator.transparentChrome,
            diveStartChromeOpacity - phaseElapsedSeconds / PetAnimator.diveChromeFadeOutDurationInSeconds
        )
        let descentElapsedSeconds = max(0, phaseElapsedSeconds - fadeOutSeconds)
        let progress = min(1, descentElapsedSeconds / PetAnimator.diveDescentDurationInSeconds)
        groundAnimationProgress = progress
        let remainingDistance = PetAnimator.fullyUnderground - diveStartGroundOffsetFraction
        groundOffsetFraction = diveStartGroundOffsetFraction
            + remainingDistance * PetAnimator.easeInTravelledDistance(progress: progress)
        guard progress >= 1 else { return }
        submerge()
    }

    private func advanceMoodBehavior(elapsedSeconds: Double, mood: PetMood, canMoveTo: (CGFloat) -> Bool) {
        switch mood {
        case .ready:
            advanceWandering(elapsedSeconds: elapsedSeconds, canMoveTo: canMoveTo)
        case .needsInput:
            settle(on: .idle)
        case .blocked:
            settle(on: .sit)
        }
    }

    private func advanceFrameClock(elapsedSeconds: Double) {
        let secondsPerFrame = 1 / PetAnimator.framesPerSecond
        frameClockInSeconds += elapsedSeconds
        while frameClockInSeconds >= secondsPerFrame {
            frameClockInSeconds -= secondsPerFrame
            frameTick += 1
        }
    }

    private func advanceBubbleBob(elapsedSeconds: Double) {
        bubblePhaseInSeconds += elapsedSeconds
        let normalizedWave = (sin(bubblePhaseInSeconds * PetGeometry.bubbleBobRadiansPerSecond) + 1) / 2
        bubbleVerticalOffset = CGFloat(normalizedWave) * PetGeometry.bubbleBobAmplitude
    }

    private func walkHome(elapsedSeconds: Double, mood: PetMood, canMoveTo: (CGFloat) -> Bool) {
        if animationName != .walk {
            animationName = .walk
            frameTick = 0
        }
        let step = PetAnimator.walkSpeedInPointsPerSecond * CGFloat(elapsedSeconds)
        let target = min(max(horizontalOffsetFromHome, -wanderHalfWidth), wanderHalfWidth)
        let remaining = target - horizontalOffsetFromHome
        if remaining != 0 {
            walkDirection = remaining < 0 ? -1 : 1
            facingLeft = walkDirection < 0
        }
        let arrives = abs(remaining) <= step
        let next = arrives ? target : horizontalOffsetFromHome + walkDirection * step
        guard canMoveTo(next) else { return }
        horizontalOffsetFromHome = next
        guard arrives else { return }
        isWalkingHome = false
        switch mood {
        case .ready: beginResting()
        case .needsInput, .blocked: break
        }
    }

    private func advanceWandering(elapsedSeconds: Double, canMoveTo: (CGFloat) -> Bool) {
        remainingActivityInSeconds -= elapsedSeconds
        switch animationName {
        case .walk:
            walk(elapsedSeconds: elapsedSeconds, canMoveTo: canMoveTo)
            if remainingActivityInSeconds <= 0 { beginResting() }
        case .idle, .wave:
            if remainingActivityInSeconds <= 0 { beginWalking() }
        case .sit, .emerge, .dive, .jump, .fall:
            beginWalking()
        }
    }

    private func settle(on restingAnimation: SpriteAnimationName) {
        guard animationName != restingAnimation else { return }
        animationName = restingAnimation
        frameTick = 0
        frameClockInSeconds = 0
        remainingActivityInSeconds = 0
    }

    private func beginWalking() {
        if walkWasBlocked {
            walkWasBlocked = false
            turnAround()
        } else if random() < PetAnimator.meanderProbability {
            turnAround()
        }
        animationName = .walk
        frameTick = 0
        remainingActivityInSeconds = randomValue(
            in: PetAnimator.minimumWalkInSeconds...PetAnimator.maximumWalkInSeconds
        )
    }

    private func beginResting() {
        frameTick = 0
        if random() < PetAnimator.waveProbability {
            animationName = .wave
            remainingActivityInSeconds = PetAnimator.waveDurationInSeconds
            return
        }
        animationName = .idle
        remainingActivityInSeconds = randomValue(
            in: PetAnimator.minimumPauseInSeconds...PetAnimator.maximumPauseInSeconds
        )
    }

    private func walk(elapsedSeconds: Double, canMoveTo: (CGFloat) -> Bool) {
        var next = horizontalOffsetFromHome + walkDirection
            * PetAnimator.walkSpeedInPointsPerSecond
            * CGFloat(elapsedSeconds)
        var turns = false
        if next > wanderHalfWidth {
            next = wanderHalfWidth
            turns = true
        } else if next < -wanderHalfWidth {
            next = -wanderHalfWidth
            turns = true
        }
        guard canMoveTo(next) else {
            walkWasBlocked = true
            return
        }
        horizontalOffsetFromHome = next
        if turns { turnAround() }
    }

    private func turnAround() {
        walkDirection *= -1
        facingLeft = walkDirection < 0
    }

    private static func clampedUnitValue(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func easeOutRemainingDistance(progress: Double) -> Double {
        let remaining = 1 - clampedUnitValue(progress)
        return remaining * remaining
    }

    private static func easeInTravelledDistance(progress: Double) -> Double {
        let travelled = clampedUnitValue(progress)
        return travelled * travelled
    }

    private static func emergeElapsedSeconds(forGroundOffsetFraction fraction: Double) -> Double {
        (1 - sqrt(clampedUnitValue(fraction))) * emergeDurationInSeconds
    }

    private static func emergeChromeOpacity(phaseElapsedSeconds: Double) -> Double {
        let fadeInStartInSeconds = emergeDurationInSeconds - emergeChromeFadeInDurationInSeconds
        let elapsedSinceFadeInStart = phaseElapsedSeconds - fadeInStartInSeconds
        guard elapsedSinceFadeInStart > 0 else { return transparentChrome }
        return clampedUnitValue(elapsedSinceFadeInStart / emergeChromeFadeInDurationInSeconds)
    }
}
