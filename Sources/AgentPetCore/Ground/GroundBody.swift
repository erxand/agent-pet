import CoreGraphics
import Foundation

package enum GroundBodyPhase: Equatable {
    case standing
    case riding
    case rising
    case falling
}

private struct FloorRise: Equatable {
    let rise: CGFloat
    let seconds: CGFloat
}

package struct GroundBody: Equatable {
    package static let gravity: CGFloat = SpaceMotion.fallAcceleration
    package static let restingTolerance: CGFloat = 1
    package static let stepUpTolerance: CGFloat = 2
    package static let jumpClearance: CGFloat = 16
    package static let springOvershoot: CGFloat = 16
    package static let rideSpeed: CGFloat = 60
    package static let floorVelocitySamples = 3
    package static let rideHoldTicks = 1
    package static let rideGap: CGFloat = 3
    package static let maximumJumpHeight: CGFloat = 160
    package static let crouchSeconds: Double = 0.07
    package static let firstFallFrameSeconds: Double = 0.15
    package static let takeoffFrame = 0
    package static let risingFrame = 1
    package static let apexFrame = 0
    package static let laterFallFrame = 1

    package private(set) var height: CGFloat
    package private(set) var velocity: CGFloat = 0
    package private(set) var phase: GroundBodyPhase = .standing
    package private(set) var isJumping = false
    package private(set) var phaseSeconds: Double = 0
    private var lastGround: CGFloat?
    private var floorRises: [FloorRise] = []
    private var ticksSincePush = 0

    package init(height: CGFloat) {
        self.height = height
    }

    package static func speedToPeak(from height: CGFloat, at apex: CGFloat) -> CGFloat {
        (2 * gravity * max(0, apex - height)).squareRoot()
    }

    package var isAirborne: Bool {
        switch phase {
        case .rising, .falling: return true
        case .standing, .riding: return false
        }
    }

    package var animationName: SpriteAnimationName? {
        switch phase {
        case .rising: return .jump
        case .falling: return .fall
        case .standing, .riding: return nil
        }
    }

    package var frameIndex: Int? {
        switch phase {
        case .rising:
            return isJumping && phaseSeconds <= GroundBody.crouchSeconds ? GroundBody.takeoffFrame : GroundBody.risingFrame
        case .falling:
            return phaseSeconds < GroundBody.firstFallFrameSeconds ? GroundBody.apexFrame : GroundBody.laterFallFrame
        case .standing, .riding:
            return nil
        }
    }

    package mutating func advance(
        elapsedSeconds: Double,
        ground newGround: CGFloat,
        floorRise: CGFloat? = nil,
        restingGround: CGFloat? = nil
    ) {
        let phaseBefore = phase
        step(elapsedSeconds: elapsedSeconds, ground: newGround, floorRise: floorRise, restingGround: restingGround)
        phaseSeconds = phase == phaseBefore ? phaseSeconds + elapsedSeconds : 0
    }

    private mutating func step(elapsedSeconds: Double, ground newGround: CGFloat, floorRise: CGFloat?, restingGround: CGFloat?) {
        guard elapsedSeconds > 0 else {
            lastGround = newGround
            if height < newGround { settle(on: newGround) }
            return
        }
        let seconds = CGFloat(elapsedSeconds)
        let rise = floorRise ?? lastGround.map { previousGround in newGround - previousGround } ?? 0
        lastGround = newGround
        floorRises.append(FloorRise(rise: rise, seconds: seconds))
        if floorRises.count > GroundBody.floorVelocitySamples { floorRises.removeFirst() }
        let floorVelocity = floorRises.reduce(0) { total, sample in total + sample.rise }
            / floorRises.reduce(0) { total, sample in total + sample.seconds }

        let launchVelocity = velocity
        velocity -= GroundBody.gravity * seconds
        height += (launchVelocity + velocity) / 2 * seconds
        if height <= newGround {
            guard floorVelocity > GroundBody.rideSpeed else {
                settle(on: newGround)
                return
            }
            let apex = max(restingGround ?? newGround, newGround) + GroundBody.springOvershoot
            height = newGround
            velocity = min(floorVelocity, GroundBody.speedToPeak(from: newGround, at: apex))
            isJumping = false
            ticksSincePush = 0
            phase = .riding
            return
        }
        ticksSincePush += 1
        switch phase {
        case .riding:
            let clearlyAbove = height - newGround > GroundBody.rideGap
            guard (ticksSincePush > GroundBody.rideHoldTicks && clearlyAbove) || velocity <= 0 else { return }
            phase = velocity > 0 ? .rising : .falling
        case .standing:
            if height - newGround > GroundBody.restingTolerance { phase = velocity > 0 ? .rising : .falling }
        case .rising:
            if velocity <= 0 { phase = .falling }
        case .falling:
            break
        }
    }

    package mutating func allowsStep(toGround nextGround: CGFloat, from groundHere: CGFloat? = nil) -> Bool {
        let standingLevel = max(height, groundHere ?? height)
        guard nextGround > standingLevel + GroundBody.stepUpTolerance else { return true }
        guard !isAirborne else { return false }
        let rise = nextGround - height
        guard rise <= GroundBody.maximumJumpHeight else { return false }
        velocity = GroundBody.speedToPeak(from: height, at: nextGround + GroundBody.jumpClearance)
        isJumping = true
        phase = .rising
        phaseSeconds = 0
        return false
    }

    private mutating func settle(on newGround: CGFloat) {
        height = newGround
        velocity = 0
        isJumping = false
        phase = .standing
    }
}

package enum GroundPlacement {
    package static func windowBottom(
        body: inout GroundBody?,
        profile: GroundProfile,
        span: ClosedRange<CGFloat>,
        elapsedSeconds: Double,
        previousProfile: GroundProfile? = nil
    ) -> CGFloat {
        switch profile.kind {
        case .flat:
            body = nil
            return profile.base
        case .dock:
            let ground = profile.height(over: span)
            var settled = body ?? GroundBody(height: ground)
            settled.advance(
                elapsedSeconds: elapsedSeconds,
                ground: ground,
                floorRise: previousProfile.map { previous in ground - previous.height(over: span) } ?? 0,
                restingGround: profile.restingHeight(over: span)
            )
            body = settled
            return settled.height
        }
    }
}
