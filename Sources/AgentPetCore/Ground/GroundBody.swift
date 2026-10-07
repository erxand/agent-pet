import CoreGraphics
import Foundation

package enum GroundBodyPhase: Equatable {
    case standing
    case riding(start: CGFloat, stillSeconds: Double)
    case rising
    case falling
}

package struct GroundBody: Equatable {
    package static let gravity: CGFloat = SpaceMotion.fallAcceleration
    package static let restingTolerance: CGFloat = 1
    package static let stepUpTolerance: CGFloat = 2
    package static let jumpClearance: CGFloat = 16
    package static let springOvershoot: CGFloat = 16
    package static let springSpeed: CGFloat = (2 * gravity * springOvershoot).squareRoot()
    package static let rideSpeed: CGFloat = 60
    package static let rideSettleSeconds: Double = 0.1
    package static let springMinimumRise: CGFloat = 8
    package static let maximumJumpHeight: CGFloat = 160

    package private(set) var height: CGFloat
    package private(set) var velocity: CGFloat = 0
    package private(set) var phase: GroundBodyPhase = .standing
    package private(set) var isJumping = false
    private var lastGround: CGFloat?

    package init(height: CGFloat) {
        self.height = height
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

    package mutating func advance(elapsedSeconds: Double, ground newGround: CGFloat) {
        guard elapsedSeconds > 0 else {
            lastGround = newGround
            if height < newGround { land(on: newGround, groundVelocity: 0, from: height) }
            return
        }
        let seconds = CGFloat(elapsedSeconds)
        let groundVelocity = lastGround.map { previousGround in (newGround - previousGround) / seconds } ?? 0
        lastGround = newGround
        let heightBeforeStep = height
        if case .riding(let start, let stillSeconds) = phase {
            guard ride(start: start, stillSeconds: stillSeconds, elapsedSeconds: elapsedSeconds, ground: newGround, groundVelocity: groundVelocity) else {
                return
            }
        }
        let launchVelocity = velocity
        velocity -= GroundBody.gravity * seconds
        height += (launchVelocity + velocity) / 2 * seconds
        if height <= newGround {
            land(on: newGround, groundVelocity: groundVelocity, from: heightBeforeStep)
            return
        }
        switch phase {
        case .standing:
            if height - newGround > GroundBody.restingTolerance { phase = velocity > 0 ? .rising : .falling }
        case .rising:
            if velocity <= 0 { phase = .falling }
        case .falling, .riding:
            break
        }
    }

    package mutating func allowsStep(toGround nextGround: CGFloat, from groundHere: CGFloat? = nil) -> Bool {
        let standingLevel = max(height, groundHere ?? height)
        guard nextGround > standingLevel + GroundBody.stepUpTolerance else { return true }
        guard !isAirborne else { return false }
        let rise = nextGround - height
        guard rise <= GroundBody.maximumJumpHeight else { return false }
        velocity = (2 * GroundBody.gravity * (rise + GroundBody.jumpClearance)).squareRoot()
        isJumping = true
        phase = .rising
        return false
    }

    private mutating func ride(
        start: CGFloat,
        stillSeconds: Double,
        elapsedSeconds: Double,
        ground newGround: CGFloat,
        groundVelocity: CGFloat
    ) -> Bool {
        if groundVelocity > 0 {
            height = newGround
            velocity = 0
            phase = .riding(start: start, stillSeconds: 0)
            return false
        }
        let pulledAway = groundVelocity < -GroundBody.rideSpeed || newGround < height - GroundBody.restingTolerance
        guard !pulledAway else {
            phase = .standing
            velocity = min(groundVelocity, 0)
            return true
        }
        height = newGround
        velocity = 0
        let settledFor = stillSeconds + elapsedSeconds
        guard settledFor >= GroundBody.rideSettleSeconds else {
            phase = .riding(start: start, stillSeconds: settledFor)
            return false
        }
        guard height - start >= GroundBody.springMinimumRise else {
            phase = .standing
            return false
        }
        velocity = GroundBody.springSpeed
        phase = .rising
        return true
    }

    private mutating func land(on newGround: CGFloat, groundVelocity: CGFloat, from heightBeforeStep: CGFloat) {
        height = newGround
        isJumping = false
        if groundVelocity > GroundBody.rideSpeed {
            velocity = 0
            phase = .riding(start: min(heightBeforeStep, newGround), stillSeconds: 0)
            return
        }
        velocity = min(groundVelocity, 0)
        phase = .standing
    }
}

package enum GroundPlacement {
    package static func windowBottom(
        body: inout GroundBody?,
        profile: GroundProfile,
        span: ClosedRange<CGFloat>,
        elapsedSeconds: Double
    ) -> CGFloat {
        switch profile.kind {
        case .flat:
            body = nil
            return profile.base
        case .dock:
            let ground = profile.height(over: span)
            var settled = body ?? GroundBody(height: ground)
            settled.advance(elapsedSeconds: elapsedSeconds, ground: ground)
            body = settled
            return settled.height
        }
    }
}
