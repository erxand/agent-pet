import CoreGraphics
import Foundation

/// Whether Shift means "go away" right now. Shift is also how capital letters get typed,
/// so it counts only held alone, for a moment, with no key pressed since it went down and
/// none just before. A pet must not leap because the cursor rests on it during typing.
package struct ShooArming: Equatable {
    package static let armDelayInSeconds: Double = 0.12
    package static let typingQuietInSeconds: Double = 0.3

    package private(set) var isArmed = false
    private var heldSeconds: Double?
    private var spoiled = false

    package init() {}

    @discardableResult
    package mutating func update(shiftIsAlone: Bool, secondsSinceKeyDown: Double, elapsedSeconds: Double) -> Bool {
        guard shiftIsAlone else {
            heldSeconds = nil
            spoiled = false
            isArmed = false
            return false
        }
        let held = heldSeconds.map { seconds in seconds + elapsedSeconds } ?? 0
        heldSeconds = held
        if secondsSinceKeyDown <= held { spoiled = true }
        isArmed = !spoiled
            && held >= ShooArming.armDelayInSeconds
            && secondsSinceKeyDown >= ShooArming.typingQuietInSeconds
        return isArmed
    }
}

package enum ShooContact: Equatable {
    case clear
    case near(gap: CGFloat)
    case touch(at: CGPoint)
    case deep(at: CGPoint)
}

package enum ShooReach {
    package static let nearRadius: CGFloat = 70
    package static let deepShare: CGFloat = 0.5

    /// What the cursor did to `body` on its way from `previous` to `current`. The whole path
    /// counts, because a fast cursor crosses a pet between two ticks.
    package static func contact(from previous: CGPoint, to current: CGPoint, body: CGRect) -> ShooContact {
        guard body.width > 0, body.height > 0 else { return .clear }
        let halfWidth = body.width / 2
        let halfHeight = body.height / 2
        let start = CGPoint(x: (previous.x - body.midX) / halfWidth, y: (previous.y - body.midY) / halfHeight)
        let end = CGPoint(x: (current.x - body.midX) / halfWidth, y: (current.y - body.midY) / halfHeight)
        func worldPoint(_ point: CGPoint) -> CGPoint {
            CGPoint(x: body.midX + point.x * halfWidth, y: body.midY + point.y * halfHeight)
        }
        let closest = closestPointToOrigin(from: start, to: end)
        if max(abs(closest.x), abs(closest.y)) <= deepShare { return .deep(at: worldPoint(closest)) }
        if max(abs(end.x), abs(end.y)) <= 1 { return .touch(at: current) }
        if let entry = entry(from: start, to: end) { return .touch(at: worldPoint(entry)) }
        let gap = hypot(
            max(abs(current.x - body.midX) - halfWidth, 0),
            max(abs(current.y - body.midY) - halfHeight, 0)
        )
        return gap <= nearRadius ? .near(gap: gap) : .clear
    }

    private static func closestPointToOrigin(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return end }
        let along = min(max(-(start.x * dx + start.y * dy) / lengthSquared, 0), 1)
        return CGPoint(x: start.x + dx * along, y: start.y + dy * along)
    }

    /// Where a path first enters the square from -1 to 1, or nil when it misses.
    private static func entry(from start: CGPoint, to end: CGPoint) -> CGPoint? {
        var enter: CGFloat = 0
        var leave: CGFloat = 1
        for (origin, delta) in [(start.x, end.x - start.x), (start.y, end.y - start.y)] {
            if delta == 0 {
                if abs(origin) > 1 { return nil }
                continue
            }
            let first = (-1 - origin) / delta
            let second = (1 - origin) / delta
            enter = max(enter, min(first, second))
            leave = min(leave, max(first, second))
            if enter > leave { return nil }
        }
        return CGPoint(x: start.x + (end.x - start.x) * enter, y: start.y + (end.y - start.y) * enter)
    }
}

package struct ShooHit: Equatable {
    package let velocity: CGVector
    package let spinRadiansPerSecond: Double

    package init(velocity: CGVector, spinRadiansPerSecond: Double) {
        self.velocity = velocity
        self.spinRadiansPerSecond = spinRadiansPerSecond
    }
}

package enum ShooImpulse {
    package static let joltBaseSpeed: CGFloat = 520
    package static let joltMaximumSpeed: CGFloat = 1300
    package static let joltCursorShare: CGFloat = 0.55
    package static let joltCursorDrag: CGFloat = 0.15
    package static let joltMinimumLift: CGFloat = 320
    package static let joltMinimumSideways: CGFloat = 220
    package static let bounceOffGroundShare: CGFloat = 0.6
    package static let launchBaseSpeed: CGFloat = 1700
    package static let launchMaximumSpeed: CGFloat = 2600
    package static let launchCursorShare: CGFloat = 0.35
    package static let launchLowestElevation: CGFloat = sin(.pi / 6)
    package static let launchLeastSideways: CGFloat = 0.34
    package static let joltRollRadiansPerSecond: Double = 5
    package static let launchRollRadiansPerSecond: Double = 11
    package static let torqueShare: Double = 0.25
    package static let maximumSpinRadiansPerSecond: Double = 24
    private static let sameSpotDistance: CGFloat = 2

    /// A push away from where the cursor met the body, harder the faster it came in. A pet
    /// on the ground hit from above bounces up, and always ends up moving sideways, or it
    /// would land back under the cursor.
    package static func jolt(
        at contact: CGPoint,
        center: CGPoint,
        cursorVelocity: CGVector,
        grounded: Bool,
        roomierSide: CGFloat
    ) -> ShooHit {
        let away = awayDirection(from: contact, center: center, cursorVelocity: cursorVelocity, roomierSide: roomierSide)
        let incoming = max(0, cursorVelocity.dx * away.dx + cursorVelocity.dy * away.dy)
        let speed = min(joltBaseSpeed + incoming * joltCursorShare, joltMaximumSpeed)
        var velocity = CGVector(
            dx: away.dx * speed + cursorVelocity.dx * joltCursorDrag,
            dy: away.dy * speed + cursorVelocity.dy * joltCursorDrag
        )
        if grounded {
            velocity.dy = max(velocity.dy < 0 ? -velocity.dy * bounceOffGroundShare : velocity.dy, joltMinimumLift)
            if abs(velocity.dx) < joltMinimumSideways {
                velocity.dx = side(of: velocity.dx, or: roomierSide) * joltMinimumSideways
            }
        }
        return ShooHit(
            velocity: velocity,
            spinRadiansPerSecond: spin(at: contact, center: center, cursorVelocity: cursorVelocity, heading: velocity.dx, roll: joltRollRadiansPerSecond)
        )
    }

    /// Away from the cursor, high and fast. Never into the ground and never straight up.
    package static func launch(
        at contact: CGPoint,
        center: CGPoint,
        cursorVelocity: CGVector,
        roomierSide: CGFloat
    ) -> ShooHit {
        var away = awayDirection(from: contact, center: center, cursorVelocity: cursorVelocity, roomierSide: roomierSide)
        let sideways = side(of: away.dx, or: roomierSide)
        if away.dy < launchLowestElevation {
            away = CGVector(dx: sideways * sqrt(1 - launchLowestElevation * launchLowestElevation), dy: launchLowestElevation)
        } else if abs(away.dx) < launchLeastSideways {
            away = CGVector(dx: sideways * launchLeastSideways, dy: sqrt(1 - launchLeastSideways * launchLeastSideways))
        }
        let speed = min(launchBaseSpeed + hypot(cursorVelocity.dx, cursorVelocity.dy) * launchCursorShare, launchMaximumSpeed)
        let velocity = CGVector(dx: away.dx * speed, dy: away.dy * speed)
        return ShooHit(
            velocity: velocity,
            spinRadiansPerSecond: spin(at: contact, center: center, cursorVelocity: cursorVelocity, heading: velocity.dx, roll: launchRollRadiansPerSecond)
        )
    }

    private static func awayDirection(from contact: CGPoint, center: CGPoint, cursorVelocity: CGVector, roomierSide: CGFloat) -> CGVector {
        let dx = center.x - contact.x
        let dy = center.y - contact.y
        let distance = hypot(dx, dy)
        if distance > sameSpotDistance { return CGVector(dx: dx / distance, dy: dy / distance) }
        let speed = hypot(cursorVelocity.dx, cursorVelocity.dy)
        if speed > 0 { return CGVector(dx: cursorVelocity.dx / speed, dy: cursorVelocity.dy / speed) }
        let diagonal = CGFloat(0.5).squareRoot()
        return CGVector(dx: roomierSide * diagonal, dy: diagonal)
    }

    private static func side(of value: CGFloat, or fallback: CGFloat) -> CGFloat {
        value == 0 ? (fallback < 0 ? -1 : 1) : (value < 0 ? -1 : 1)
    }

    /// Off-center hits turn the pet the way the cursor's push would, and every hit rolls it
    /// toward where it is going. Positive is counterclockwise, like the view's rotation.
    private static func spin(at contact: CGPoint, center: CGPoint, cursorVelocity: CGVector, heading: CGFloat, roll: Double) -> Double {
        let arm = CGVector(dx: contact.x - center.x, dy: contact.y - center.y)
        let radius = max(hypot(arm.dx, arm.dy), 1)
        let torque = Double((arm.dx * cursorVelocity.dy - arm.dy * cursorVelocity.dx) / (radius * radius))
        let rolling = heading == 0 ? 0 : (heading > 0 ? -roll : roll)
        return min(max(torque * torqueShare + rolling, -maximumSpinRadiansPerSecond), maximumSpinRadiansPerSecond)
    }
}

package enum ShooFlightPhase: Equatable {
    case airborne
    case skidding
    case landed
}

package struct ShooFlight: Equatable {
    package static let gravity = SpaceMotion.fallAcceleration
    package static let maximumSpeed: CGFloat = 3200
    package static let airDragPerSecond: Double = 0.35
    package static let wallRestitution: CGFloat = 0.6
    package static let floorRestitution: CGFloat = 0.52
    package static let floorFriction: CGFloat = 0.72
    package static let floorSpinKeeps: Double = 0.55
    package static let wallSpinKeeps: Double = -0.7
    package static let settleImpactSpeed: CGFloat = 170
    package static let straightenImpactSpeed: CGFloat = 600
    package static let straightenRadiansPerSecond: Double = 9
    package static let skidFrictionPerSecond: Double = 7
    package static let skidStopSpeed: CGFloat = 18
    package static let raisedFloorTolerance: CGFloat = 8
    package static let longestStepInSeconds: Double = 1.0 / 60.0

    package private(set) var center: CGPoint
    package private(set) var velocity: CGVector
    package private(set) var rotationInRadians: Double = 0
    package private(set) var spinRadiansPerSecond: Double
    package private(set) var phase: ShooFlightPhase = .airborne
    package let facingLeft: Bool
    private var isStraightening = false

    package init(from center: CGPoint, hit: ShooHit, facingLeft: Bool) {
        self.center = center
        velocity = ShooFlight.capped(hit.velocity)
        spinRadiansPerSecond = hit.spinRadiansPerSecond
        self.facingLeft = facingLeft
    }

    package var animationName: SpriteAnimationName {
        switch phase {
        case .airborne: return velocity.dy > 0 ? .jump : .fall
        case .skidding, .landed: return .idle
        }
    }

    package var frameIndex: Int? {
        phase == .airborne ? GroundBody.risingFrame : nil
    }

    package var hasLanded: Bool { phase == .landed }

    /// Another hit in the air replaces the pet's course: the cursor knocked it somewhere new.
    package mutating func take(_ hit: ShooHit) {
        velocity = ShooFlight.capped(hit.velocity)
        spinRadiansPerSecond = hit.spinRadiansPerSecond
        phase = .airborne
        isStraightening = false
    }

    package mutating func accelerate(by change: CGVector) {
        guard phase == .airborne else { return }
        velocity = ShooFlight.capped(CGVector(dx: velocity.dx + change.dx, dy: velocity.dy + change.dy))
    }

    /// `walls` and `ceiling` bound the pet's center, and `floorAt` is the lowest its center
    /// may be at a given x. That can jump up at the end of the Dock, which stops a low
    /// flight like a wall rather than lifting the pet onto it.
    package mutating func advance(
        elapsedSeconds: Double,
        walls: ClosedRange<CGFloat>,
        ceiling: CGFloat,
        floorAt: (CGFloat) -> CGFloat
    ) {
        var remaining = elapsedSeconds
        while remaining > 0, phase != .landed {
            let step = min(remaining, ShooFlight.longestStepInSeconds)
            remaining -= step
            switch phase {
            case .airborne: fly(seconds: step, walls: walls, ceiling: ceiling, floorAt: floorAt)
            case .skidding: skid(seconds: step, walls: walls, floorAt: floorAt)
            case .landed: break
            }
        }
    }

    private mutating func fly(seconds: Double, walls: ClosedRange<CGFloat>, ceiling: CGFloat, floorAt: (CGFloat) -> CGFloat) {
        let dt = CGFloat(seconds)
        velocity.dy -= ShooFlight.gravity * dt
        velocity.dx *= CGFloat(exp(-ShooFlight.airDragPerSecond * seconds))
        center.x = movedAcross(walls: walls, dt: dt, floorAt: floorAt)
        var nextY = center.y + velocity.dy * dt
        if nextY > ceiling {
            nextY = ceiling
            velocity.dy = -abs(velocity.dy) * ShooFlight.wallRestitution
        }
        let floor = floorAt(center.x)
        if nextY <= floor {
            nextY = floor
            let impact = max(0, -velocity.dy)
            velocity.dx *= ShooFlight.floorFriction
            spinRadiansPerSecond *= ShooFlight.floorSpinKeeps
            if impact < ShooFlight.straightenImpactSpeed { isStraightening = true }
            if impact < ShooFlight.settleImpactSpeed {
                velocity.dy = 0
                phase = .skidding
            } else {
                velocity.dy = impact * ShooFlight.floorRestitution
            }
        }
        center.y = nextY
        turn(seconds: seconds)
    }

    private mutating func skid(seconds: Double, walls: ClosedRange<CGFloat>, floorAt: (CGFloat) -> CGFloat) {
        velocity.dx *= CGFloat(exp(-ShooFlight.skidFrictionPerSecond * seconds))
        center.x = movedAcross(walls: walls, dt: CGFloat(seconds), floorAt: floorAt)
        let floor = floorAt(center.x)
        if center.y > floor + ShooFlight.raisedFloorTolerance {
            phase = .airborne
            return
        }
        center.y = floor
        isStraightening = true
        turn(seconds: seconds)
        if abs(velocity.dx) < ShooFlight.skidStopSpeed, rotationInRadians == 0 {
            velocity = CGVector(dx: 0, dy: 0)
            phase = .landed
        }
    }

    private mutating func movedAcross(walls: ClosedRange<CGFloat>, dt: CGFloat, floorAt: (CGFloat) -> CGFloat) -> CGFloat {
        var nextX = center.x + velocity.dx * dt
        if nextX < walls.lowerBound || nextX > walls.upperBound {
            nextX = min(max(nextX, walls.lowerBound), walls.upperBound)
            velocity.dx = (nextX == walls.lowerBound ? abs(velocity.dx) : -abs(velocity.dx)) * ShooFlight.wallRestitution
            spinRadiansPerSecond *= ShooFlight.wallSpinKeeps
        }
        if floorAt(nextX) > center.y + ShooFlight.raisedFloorTolerance {
            velocity.dx = -velocity.dx * ShooFlight.wallRestitution
            spinRadiansPerSecond *= ShooFlight.wallSpinKeeps
            return center.x
        }
        return nextX
    }

    private mutating func turn(seconds: Double) {
        if isStraightening {
            rotationInRadians = SpaceMotion.turnedTowardUpright(
                rotationInRadians,
                byAtMost: ShooFlight.straightenRadiansPerSecond * seconds
            )
        } else {
            rotationInRadians += spinRadiansPerSecond * seconds
        }
    }

    private static func capped(_ velocity: CGVector) -> CGVector {
        let speed = hypot(velocity.dx, velocity.dy)
        guard speed > maximumSpeed else { return velocity }
        return CGVector(dx: velocity.dx / speed * maximumSpeed, dy: velocity.dy / speed * maximumSpeed)
    }
}

package enum ShooRun {
    package static let slowestSpeed: CGFloat = 140
    package static let fastestSpeed: CGFloat = 460
    package static let airPushPerSecond: CGFloat = 1800
    private static let underCursorDistance: CGFloat = 3

    package static func closeness(gap: CGFloat) -> CGFloat {
        let share = 1 - min(max(gap, 0), ShooReach.nearRadius) / ShooReach.nearRadius
        return share * share
    }

    package static func speed(gap: CGFloat) -> CGFloat {
        slowestSpeed + (fastestSpeed - slowestSpeed) * closeness(gap: gap)
    }

    package static func direction(petX: CGFloat, cursorX: CGFloat, roomierSide: CGFloat) -> CGFloat {
        let away = petX - cursorX
        if abs(away) < underCursorDistance { return roomierSide < 0 ? -1 : 1 }
        return away < 0 ? -1 : 1
    }

    /// A push straight away from the cursor while the pet is in the air.
    package static func airPush(from cursor: CGPoint, center: CGPoint, gap: CGFloat, elapsedSeconds: Double) -> CGVector {
        let dx = center.x - cursor.x
        let dy = center.y - cursor.y
        let distance = hypot(dx, dy)
        guard distance > 0 else { return CGVector(dx: 0, dy: 0) }
        let change = airPushPerSecond * closeness(gap: gap) * CGFloat(elapsedSeconds)
        return CGVector(dx: dx / distance * change, dy: dy / distance * change)
    }
}

extension PixelFrame {
    /// The drawn part of the frame in points, with the sprite's own square as the origin
    /// and y up. A frame with nothing drawn is its whole square.
    package func inkBounds(sideLengthInPoints side: CGFloat) -> CGRect {
        let clear = PixelInk.clear.rawValue
        var minColumn = sideLength, maxColumn = -1, minRow = sideLength, maxRow = -1
        for row in 0..<sideLength {
            for column in 0..<sideLength where character(column: column, row: row) != clear {
                minColumn = min(minColumn, column)
                maxColumn = max(maxColumn, column)
                minRow = min(minRow, row)
                maxRow = max(maxRow, row)
            }
        }
        guard maxColumn >= 0 else { return CGRect(x: 0, y: 0, width: side, height: side) }
        let pixel = side / CGFloat(sideLength)
        return CGRect(
            x: CGFloat(minColumn) * pixel,
            y: CGFloat(sideLength - 1 - maxRow) * pixel,
            width: CGFloat(maxColumn - minColumn + 1) * pixel,
            height: CGFloat(maxRow - minRow + 1) * pixel
        )
    }
}
