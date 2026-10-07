import CoreGraphics
import Foundation

package enum SpacePhase: Equatable {
    case floating
    case falling
    case landed
}

package struct SpaceArea: Equatable {
    package let lowestCenter: CGPoint
    package let highestCenter: CGPoint

    package init(lowestCenter: CGPoint, highestCenter: CGPoint) {
        self.lowestCenter = lowestCenter
        self.highestCenter = CGPoint(x: max(lowestCenter.x, highestCenter.x), y: max(lowestCenter.y, highestCenter.y))
    }

    package var groundCenterY: CGFloat { lowestCenter.y }

    package func contains(_ center: CGPoint) -> Bool {
        center.x >= lowestCenter.x && center.x <= highestCenter.x
            && center.y >= lowestCenter.y && center.y <= highestCenter.y
    }

    func clamped(_ center: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(center.x, lowestCenter.x), highestCenter.x),
            y: min(max(center.y, lowestCenter.y), highestCenter.y)
        )
    }
}

package struct SpaceMotion: Equatable {
    package static let minimumDriftSpeed: CGFloat = 24
    package static let maximumDriftSpeed: CGFloat = 48
    package static let minimumSpinRadiansPerSecond: Double = 0.25
    package static let maximumSpinRadiansPerSecond: Double = 0.6
    package static let lowestLaunchAngle: Double = Double.pi / 6
    package static let highestLaunchAngle: Double = Double.pi * 5 / 6
    package static let fallAcceleration: CGFloat = 1400
    package static let fallDriftDampingPerSecond: CGFloat = 2
    package static let uprightRadiansPerSecond: Double = 3
    package static let bounceRestitution: CGFloat = 0.97
    package static let cruiseRecoveryPerSecond: Double = 0.5
    package static let maximumBounceSpeed: CGFloat = 72
    private static let fullTurn = Double.pi * 2
    private static let fnv1aOffsetBasis: UInt64 = 0xcbf29ce484222325
    private static let fnv1aPrime: UInt64 = 0x100000001b3

    package private(set) var center: CGPoint
    package private(set) var velocity: CGVector
    package private(set) var rotationInRadians: Double = 0
    package private(set) var spinRadiansPerSecond: Double
    package private(set) var phase: SpacePhase = .floating
    package let facingLeft: Bool
    package private(set) var cruiseSpeed: CGFloat

    package init(launchingFrom center: CGPoint, seed: UInt64, facingLeft: Bool = false) {
        var generator = SeededGenerator(seed: seed)
        let speed = CGFloat.random(in: SpaceMotion.minimumDriftSpeed...SpaceMotion.maximumDriftSpeed, using: &generator)
        let angle = Double.random(in: SpaceMotion.lowestLaunchAngle...SpaceMotion.highestLaunchAngle, using: &generator)
        let spin = Double.random(
            in: SpaceMotion.minimumSpinRadiansPerSecond...SpaceMotion.maximumSpinRadiansPerSecond,
            using: &generator
        )
        let spinsClockwise = Bool.random(using: &generator)
        self.center = center
        velocity = CGVector(dx: speed * CGFloat(cos(angle)), dy: speed * CGFloat(sin(angle)))
        spinRadiansPerSecond = spinsClockwise ? -spin : spin
        self.facingLeft = facingLeft
        cruiseSpeed = speed
    }

    package static func seed(forPetKey petKey: String) -> UInt64 {
        var hash = fnv1aOffsetBasis
        for byte in petKey.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* fnv1aPrime
        }
        return hash
    }

    package var animationName: SpriteAnimationName {
        switch phase {
        case .floating, .landed: return .idle
        case .falling: return .fall
        }
    }

    package var isOnGround: Bool {
        phase == .landed
    }

    package mutating func returnToGround() {
        switch phase {
        case .floating: phase = .falling
        case .falling, .landed: return
        }
    }

    package mutating func advance(elapsedSeconds: Double, area: SpaceArea) {
        guard elapsedSeconds > 0 else { return }
        switch phase {
        case .floating: drift(elapsedSeconds: elapsedSeconds, area: area)
        case .falling: fall(elapsedSeconds: elapsedSeconds, area: area)
        case .landed: return
        }
    }

    private mutating func drift(elapsedSeconds: Double, area: SpaceArea) {
        easeTowardCruiseSpeed(elapsedSeconds: elapsedSeconds)
        let seconds = CGFloat(elapsedSeconds)
        var next = CGPoint(x: center.x + velocity.dx * seconds, y: center.y + velocity.dy * seconds)
        if next.x < area.lowestCenter.x || next.x > area.highestCenter.x {
            velocity.dx = next.x < area.lowestCenter.x ? abs(velocity.dx) : -abs(velocity.dx)
        }
        if next.y < area.lowestCenter.y || next.y > area.highestCenter.y {
            velocity.dy = next.y < area.lowestCenter.y ? abs(velocity.dy) : -abs(velocity.dy)
        }
        next = area.clamped(next)
        center = next
        rotationInRadians = (rotationInRadians + spinRadiansPerSecond * elapsedSeconds)
            .truncatingRemainder(dividingBy: SpaceMotion.fullTurn)
    }

    private mutating func fall(elapsedSeconds: Double, area: SpaceArea) {
        let seconds = CGFloat(elapsedSeconds)
        velocity.dy -= SpaceMotion.fallAcceleration * seconds
        velocity.dx *= CGFloat(exp(-Double(SpaceMotion.fallDriftDampingPerSecond) * elapsedSeconds))
        center = CGPoint(
            x: min(max(center.x + velocity.dx * seconds, area.lowestCenter.x), area.highestCenter.x),
            y: center.y + velocity.dy * seconds
        )
        rotationInRadians = SpaceMotion.turnedTowardUpright(
            rotationInRadians,
            byAtMost: SpaceMotion.uprightRadiansPerSecond * elapsedSeconds
        )
        guard center.y <= area.groundCenterY else { return }
        center.y = area.groundCenterY
        velocity = CGVector(dx: 0, dy: 0)
        rotationInRadians = 0
        phase = .landed
    }

    package static func collide(_ motions: inout [SpaceMotion], minimumDistance: (Int, Int) -> CGFloat) {
        for first in motions.indices {
            for second in motions.indices where second > first {
                var other = motions[second]
                motions[first].bounce(off: &other, minimumDistance: minimumDistance(first, second))
                motions[second] = other
            }
        }
    }

    package mutating func bounce(off other: inout SpaceMotion, minimumDistance: CGFloat) {
        guard phase == .floating, other.phase == .floating else { return }
        let offset = CGVector(dx: other.center.x - center.x, dy: other.center.y - center.y)
        let distance = hypot(offset.dx, offset.dy)
        guard distance > 0, distance < minimumDistance else { return }
        let normal = CGVector(dx: offset.dx / distance, dy: offset.dy / distance)
        let push = (minimumDistance - distance) / 2
        center = CGPoint(x: center.x - normal.dx * push, y: center.y - normal.dy * push)
        other.center = CGPoint(x: other.center.x + normal.dx * push, y: other.center.y + normal.dy * push)
        let approachSpeed = (velocity.dx - other.velocity.dx) * normal.dx + (velocity.dy - other.velocity.dy) * normal.dy
        guard approachSpeed > 0 else { return }
        let impulse = approachSpeed * (1 + SpaceMotion.bounceRestitution) / 2
        velocity = SpaceMotion.capped(CGVector(dx: velocity.dx - impulse * normal.dx, dy: velocity.dy - impulse * normal.dy))
        other.velocity = SpaceMotion.capped(
            CGVector(dx: other.velocity.dx + impulse * normal.dx, dy: other.velocity.dy + impulse * normal.dy)
        )
    }

    private mutating func easeTowardCruiseSpeed(elapsedSeconds: Double) {
        let speed = hypot(velocity.dx, velocity.dy)
        guard speed > 0, speed != cruiseSpeed else { return }
        let blend = CGFloat(1 - exp(-SpaceMotion.cruiseRecoveryPerSecond * elapsedSeconds))
        let scale = (speed + (cruiseSpeed - speed) * blend) / speed
        velocity = CGVector(dx: velocity.dx * scale, dy: velocity.dy * scale)
    }

    private static func capped(_ velocity: CGVector) -> CGVector {
        let speed = hypot(velocity.dx, velocity.dy)
        guard speed > maximumBounceSpeed else { return velocity }
        let scale = maximumBounceSpeed / speed
        return CGVector(dx: velocity.dx * scale, dy: velocity.dy * scale)
    }

    package static func turnedTowardUpright(_ rotation: Double, byAtMost maximumTurn: Double) -> Double {
        let offset = remainder(rotation, fullTurn)
        guard abs(offset) > maximumTurn else { return 0 }
        return offset > 0 ? offset - maximumTurn : offset + maximumTurn
    }
}

package struct SeededGenerator: RandomNumberGenerator {
    private static let splitMix64Increment: UInt64 = 0x9E3779B97F4A7C15
    private static let splitMix64FirstMultiplier: UInt64 = 0xBF58476D1CE4E5B9
    private static let splitMix64SecondMultiplier: UInt64 = 0x94D049BB133111EB

    private var state: UInt64

    package init(seed: UInt64) {
        state = seed
    }

    package mutating func next() -> UInt64 {
        state = state &+ SeededGenerator.splitMix64Increment
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* SeededGenerator.splitMix64FirstMultiplier
        mixed = (mixed ^ (mixed >> 27)) &* SeededGenerator.splitMix64SecondMultiplier
        return mixed ^ (mixed >> 31)
    }
}
