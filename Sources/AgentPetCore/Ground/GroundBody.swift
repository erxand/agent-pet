import CoreGraphics
import Foundation

package struct GroundBody: Equatable {
    package static let gravity: CGFloat = SpaceMotion.fallAcceleration
    package static let maximumSpringSpeed: CGFloat = 260
    package static let restingTolerance: CGFloat = 1
    package static let stepUpTolerance: CGFloat = 2
    package static let jumpClearance: CGFloat = 10
    package static let maximumJumpHeight: CGFloat = 160

    package private(set) var height: CGFloat
    package private(set) var velocity: CGFloat = 0
    package private(set) var isJumping = false
    private var ground: CGFloat
    private var lastGround: CGFloat?

    package init(height: CGFloat) {
        self.height = height
        ground = height
    }

    package var isAirborne: Bool {
        isJumping || height - ground > GroundBody.restingTolerance
    }

    package var animationName: SpriteAnimationName? {
        guard isAirborne else { return nil }
        return velocity > 0 ? .jump : .fall
    }

    package mutating func advance(elapsedSeconds: Double, ground newGround: CGFloat) {
        ground = newGround
        guard elapsedSeconds > 0 else {
            lastGround = newGround
            if height < newGround { land(on: newGround, groundVelocity: 0) }
            return
        }
        let seconds = CGFloat(elapsedSeconds)
        let groundVelocity = lastGround.map { previousGround in (newGround - previousGround) / seconds } ?? 0
        lastGround = newGround
        velocity -= GroundBody.gravity * seconds
        height += velocity * seconds
        guard height <= newGround else { return }
        land(on: newGround, groundVelocity: groundVelocity)
    }

    package mutating func allowsStep(toGround nextGround: CGFloat) -> Bool {
        guard nextGround > height + GroundBody.stepUpTolerance else { return true }
        guard !isAirborne else { return false }
        let rise = nextGround - height
        guard rise <= GroundBody.maximumJumpHeight else { return false }
        velocity = (2 * GroundBody.gravity * (rise + GroundBody.jumpClearance)).squareRoot()
        isJumping = true
        return false
    }

    private mutating func land(on newGround: CGFloat, groundVelocity: CGFloat) {
        height = newGround
        velocity = min(groundVelocity, GroundBody.maximumSpringSpeed)
        isJumping = false
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
