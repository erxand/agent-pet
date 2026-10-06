import CoreGraphics
import Foundation

package enum SpacePhase: Equatable {
    case floating
    case falling
    case walkingHome
    case home
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
    package static let walkSpeedInPointsPerSecond: CGFloat = 40
    private static let fullTurn = Double.pi * 2

    package private(set) var center: CGPoint
    package private(set) var velocity: CGVector
    package private(set) var rotationInRadians: Double = 0
    package private(set) var spinRadiansPerSecond: Double
    package private(set) var phase: SpacePhase = .floating
    package private(set) var facingLeft: Bool

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
    }

    package static func seed(forPetKey petKey: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in petKey.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    package var animationName: SpriteAnimationName {
        switch phase {
        case .floating, .falling, .home: return .idle
        case .walkingHome: return .walk
        }
    }

    package var isOnGround: Bool {
        switch phase {
        case .walkingHome, .home: return true
        case .floating, .falling: return false
        }
    }

    package mutating func returnToGround() {
        switch phase {
        case .floating: phase = .falling
        case .falling, .walkingHome, .home: return
        }
    }

    package mutating func advance(elapsedSeconds: Double, area: SpaceArea, homeCenterX: CGFloat) {
        guard elapsedSeconds > 0 else { return }
        switch phase {
        case .floating: drift(elapsedSeconds: elapsedSeconds, area: area)
        case .falling: fall(elapsedSeconds: elapsedSeconds, area: area)
        case .walkingHome: walkHome(elapsedSeconds: elapsedSeconds, homeCenterX: homeCenterX)
        case .home: return
        }
    }

    private mutating func drift(elapsedSeconds: Double, area: SpaceArea) {
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
        phase = .walkingHome
    }

    private mutating func walkHome(elapsedSeconds: Double, homeCenterX: CGFloat) {
        let remaining = homeCenterX - center.x
        let step = SpaceMotion.walkSpeedInPointsPerSecond * CGFloat(elapsedSeconds)
        guard abs(remaining) > step else {
            center.x = homeCenterX
            phase = .home
            return
        }
        facingLeft = remaining < 0
        center.x += remaining < 0 ? -step : step
    }

    package static func turnedTowardUpright(_ rotation: Double, byAtMost maximumTurn: Double) -> Double {
        let offset = remainder(rotation, fullTurn)
        guard abs(offset) > maximumTurn else { return 0 }
        return offset > 0 ? offset - maximumTurn : offset + maximumTurn
    }
}

package struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    package init(seed: UInt64) {
        state = seed
    }

    package mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58476D1CE4E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D049BB133111EB
        return mixed ^ (mixed >> 31)
    }
}
