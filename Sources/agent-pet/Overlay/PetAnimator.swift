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
    private static let walkSpeedInPointsPerSecond: CGFloat = 40
    private static let emergeDurationInSeconds: Double = 0.45
    private static let emergeChromeFadeInDurationInSeconds: Double = 0.15
    private static let diveChromeFadeOutDurationInSeconds: Double = 0.1
    private static let diveDescentDurationInSeconds: Double = 0.35
    // The longest step an emerge or a dive takes in one tick. The overlay's
    // animation timer is charged for whatever the main thread did between two
    // ticks (a reconcile, a slow pack folder, a busy Mac), and a dive is only
    // 450 ms long, so without this one late tick could carry a pet straight
    // through its dive frames and it would seem to vanish. A slow tick now
    // slows the dive down instead of skipping it.
    static let maximumGroundStepInSeconds: Double = 1.0 / 15.0
    private static let minimumPauseInSeconds: Double = 1
    private static let maximumPauseInSeconds: Double = 3
    private static let minimumWalkInSeconds: Double = 1.5
    private static let maximumWalkInSeconds: Double = 5
    private static let waveDurationInSeconds: Double = 1.5
    private static let waveProbability: Double = 0.35
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

    private var frameClockInSeconds: Double = 0
    private var remainingActivityInSeconds: Double = 0
    private var bubblePhaseInSeconds: Double = 0
    private var phaseElapsedSeconds: Double = 0
    private var walkDirection: CGFloat = 1
    private var diveStartGroundOffsetFraction: Double = PetAnimator.fullyAboveGround
    private var diveStartChromeOpacity: Double = PetAnimator.opaqueChrome

    init() {
        startEmerging(fromGroundOffsetFraction: PetAnimator.fullyUnderground)
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

    func requestDive() {
        switch groundPhase {
        case .diving, .submerged:
            return
        case .emerging, .grounded:
            startDiving(fromGroundOffsetFraction: groundOffsetFraction)
        }
    }

    func advance(elapsedSeconds unclampedElapsedSeconds: Double, mood: PetMood) {
        let elapsedSeconds = playsGroundAnimationOnce
            ? min(unclampedElapsedSeconds, PetAnimator.maximumGroundStepInSeconds)
            : unclampedElapsedSeconds
        advanceFrameClock(elapsedSeconds: elapsedSeconds)
        advanceBubbleBob(elapsedSeconds: elapsedSeconds)

        switch groundPhase {
        case .emerging:
            advanceEmerging(elapsedSeconds: elapsedSeconds)
        case .grounded:
            advanceMoodBehavior(elapsedSeconds: elapsedSeconds, mood: mood)
        case .diving:
            advanceDiving(elapsedSeconds: elapsedSeconds)
        case .submerged:
            return
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

    // A dive always plays every dive frame, from wherever the pet is. A pet
    // hidden while it was still coming up (a click, a prompt, or its pane being
    // focused mid-emerge) used to start its dive at the point that matched its
    // height, which skipped the first frames and, early in an emerge, all of
    // them. Now it sinks from its current height over the whole descent, and
    // its label fades from its current opacity. Only a pet with nothing above
    // ground yet goes straight under, since there is nothing to see dive.
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

    private func advanceMoodBehavior(elapsedSeconds: Double, mood: PetMood) {
        switch mood {
        case .ready:
            advanceWandering(elapsedSeconds: elapsedSeconds)
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

    private func advanceWandering(elapsedSeconds: Double) {
        remainingActivityInSeconds -= elapsedSeconds
        switch animationName {
        case .walk:
            walk(elapsedSeconds: elapsedSeconds)
            if remainingActivityInSeconds <= 0 { beginResting() }
        case .idle, .wave:
            if remainingActivityInSeconds <= 0 { beginWalking() }
        case .sit, .emerge, .dive:
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
        animationName = .walk
        frameTick = 0
        remainingActivityInSeconds = Double.random(
            in: PetAnimator.minimumWalkInSeconds...PetAnimator.maximumWalkInSeconds
        )
    }

    private func beginResting() {
        frameTick = 0
        if Double.random(in: 0...1) < PetAnimator.waveProbability {
            animationName = .wave
            remainingActivityInSeconds = PetAnimator.waveDurationInSeconds
            return
        }
        animationName = .idle
        remainingActivityInSeconds = Double.random(
            in: PetAnimator.minimumPauseInSeconds...PetAnimator.maximumPauseInSeconds
        )
    }

    private func walk(elapsedSeconds: Double) {
        horizontalOffsetFromHome += walkDirection
            * PetAnimator.walkSpeedInPointsPerSecond
            * CGFloat(elapsedSeconds)
        if horizontalOffsetFromHome > LaneLayout.wanderHalfWidth {
            horizontalOffsetFromHome = LaneLayout.wanderHalfWidth
            turnAround()
        } else if horizontalOffsetFromHome < -LaneLayout.wanderHalfWidth {
            horizontalOffsetFromHome = -LaneLayout.wanderHalfWidth
            turnAround()
        }
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
