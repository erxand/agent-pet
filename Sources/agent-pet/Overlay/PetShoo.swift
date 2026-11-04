import AgentPetCore
import AppKit

struct ShooInput: Equatable {
    let cursor: CGPoint
    let shiftIsHeld: Bool
    let shiftIsAlone: Bool
    let secondsSinceKeyDown: Double
}

protocol ShooInputSource {
    func sample() -> ShooInput
}

/// Reads the keyboard and the cursor by asking the window server. None of it needs a
/// macOS permission, unlike an event tap.
struct LiveShooInput: ShooInputSource {
    func sample() -> ShooInput {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let shiftIsHeld = flags.contains(.maskShift)
        return ShooInput(
            cursor: NSEvent.mouseLocation,
            shiftIsHeld: shiftIsHeld,
            shiftIsAlone: shiftIsHeld && flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate]),
            secondsSinceKeyDown: CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        )
    }
}

struct ShooStage {
    let visibleFrame: CGRect
    let floorUnder: (PetPresence, CGFloat) -> CGFloat
}

enum ShooOrder: Equatable {
    case free
    case flying
    case landed
    case stayPut
    case flee(direction: CGFloat, speed: CGFloat, range: ClosedRange<CGFloat>)
}

/// "Go away, I'm trying to click here." While Shift is held a pet near the cursor runs, one
/// the cursor touches is knocked away from where it was hit, and one the cursor gets deep
/// inside is launched. It then stays away for a while, so the spot stays clear to click.
final class PetShooDirector {
    static let staysAwayInSeconds: TimeInterval = 6
    static let hitCooldownInSeconds: TimeInterval = 0.12
    private static let cursorSmoothing: CGFloat = 0.5

    private let input: ShooInputSource
    private var bodies: [String: CGRect] = [:]
    private var arming = ShooArming()
    private var isEnabled = false
    private var shiftIsHeld = false
    private var cursor: CGPoint?
    private var previousCursor: CGPoint?
    private var cursorVelocity = CGVector(dx: 0, dy: 0)

    init(input: ShooInputSource = LiveShooInput()) {
        self.input = input
    }

    func beginTick(enabled: Bool, elapsedSeconds: Double) {
        isEnabled = enabled
        guard enabled else {
            arming = ShooArming()
            shiftIsHeld = false
            cursor = nil
            previousCursor = nil
            cursorVelocity = CGVector(dx: 0, dy: 0)
            return
        }
        let sample = input.sample()
        shiftIsHeld = sample.shiftIsHeld
        arming.update(
            shiftIsAlone: sample.shiftIsAlone,
            secondsSinceKeyDown: sample.secondsSinceKeyDown,
            elapsedSeconds: elapsedSeconds
        )
        let before = cursor ?? sample.cursor
        if elapsedSeconds > 0 {
            let smoothing = PetShooDirector.cursorSmoothing
            cursorVelocity = CGVector(
                dx: cursorVelocity.dx * smoothing + (sample.cursor.x - before.x) / CGFloat(elapsedSeconds) * (1 - smoothing),
                dy: cursorVelocity.dy * smoothing + (sample.cursor.y - before.y) / CGFloat(elapsedSeconds) * (1 - smoothing)
            )
        }
        previousCursor = before
        cursor = sample.cursor
    }

    /// Clicks go through a pet while Shift is held or while it is flying: the whole point is
    /// to reach what is under it.
    func keepsClicksOff(_ presence: PetPresence) -> Bool {
        isEnabled && shiftIsHeld || presence.shooFlight != nil
    }

    func forgetBodies() {
        bodies.removeAll()
    }

    func advance(_ presence: PetPresence, elapsedSeconds: Double, now: TimeInterval, stage: ShooStage) -> ShooOrder {
        guard presence.animator.isGrounded else {
            leaveFlight(presence)
            return .free
        }
        let center = spriteCenter(of: presence)
        let contact = currentContact(for: presence, center: center, now: now)
        if presence.spaceMotion != nil {
            return shoveFloating(presence, contact: contact, center: center, elapsedSeconds: elapsedSeconds, now: now, stage: stage)
        }
        switch contact {
        case .touch(let point):
            let hit = ShooImpulse.jolt(
                at: point,
                center: center,
                cursorVelocity: cursorVelocity,
                grounded: presence.shooFlight == nil,
                roomierSide: roomierSide(at: center.x, stage: stage)
            )
            take(hit, presence: presence, center: center, now: now)
        case .deep(let point):
            let hit = ShooImpulse.launch(
                at: point,
                center: center,
                cursorVelocity: cursorVelocity,
                roomierSide: roomierSide(at: center.x, stage: stage)
            )
            take(hit, presence: presence, center: center, now: now)
        case .near, .clear:
            break
        }
        if presence.shooFlight != nil {
            if case .near(let gap) = contact, let cursor {
                presence.shooFlight?.accelerate(by: ShooRun.airPush(from: cursor, center: center, gap: gap, elapsedSeconds: elapsedSeconds))
            }
            return fly(presence, elapsedSeconds: elapsedSeconds, now: now, stage: stage)
        }
        if case .near(let gap) = contact, let cursor {
            presence.shooStaysAwayUntil = now + PetShooDirector.staysAwayInSeconds
            return .flee(
                direction: ShooRun.direction(petX: center.x, cursorX: cursor.x, roomierSide: roomierSide(at: center.x, stage: stage)),
                speed: ShooRun.speed(gap: gap),
                range: offsetRange(of: presence, stage: stage)
            )
        }
        guard let until = presence.shooStaysAwayUntil else { return .free }
        guard now < until else {
            presence.shooStaysAwayUntil = nil
            presence.animator.stand(atHorizontalOffsetFromHome: presence.animator.horizontalOffsetFromHome)
            return .free
        }
        return .stayPut
    }

    func spriteCenter(of presence: PetPresence) -> CGPoint {
        if let flight = presence.shooFlight { return flight.center }
        let frame = presence.window.frame
        return CGPoint(
            x: frame.midX,
            y: frame.minY + PetShooDirector.spriteCenterAboveFeet(presence)
        )
    }

    private static func spriteCenterAboveFeet(_ presence: PetPresence) -> CGFloat {
        let appearance = presence.view.petAppearance
        return PetGeometry.spriteBaseline(layout: appearance.labelLayout) + appearance.spriteSideLength / 2
    }

    func leaveFlight(_ presence: PetPresence) {
        guard let flight = presence.shooFlight else { return }
        presence.shooFlight = nil
        presence.view.update(spaceRotationInRadians: nil)
        presence.animator.stand(atHorizontalOffsetFromHome: flight.center.x - presence.homeHorizontalCenter)
        let size = presence.view.preferredSize
        presence.window.setFrame(
            CGRect(
                x: (flight.center.x - size.width / 2).rounded(),
                y: (flight.center.y - PetShooDirector.spriteCenterAboveFeet(presence)).rounded(),
                width: size.width,
                height: size.height
            ),
            display: false
        )
    }

    private func currentContact(for presence: PetPresence, center: CGPoint, now: TimeInterval) -> ShooContact {
        guard isEnabled, arming.isArmed, let cursor, let previousCursor else { return .clear }
        let contact = ShooReach.contact(from: previousCursor, to: cursor, body: body(of: presence, center: center))
        switch contact {
        case .touch, .deep:
            if let next = presence.shooNextHitAt, now < next { return .clear }
        case .near, .clear:
            break
        }
        return contact
    }

    private func body(of presence: PetPresence, center: CGPoint) -> CGRect {
        let side = presence.view.petAppearance.spriteSideLength
        let ink: CGRect
        if let known = bodies[presence.spritePackName] {
            ink = known
        } else {
            ink = presence.spriteSheet.idle.first?.inkBounds(sideLengthInPoints: side)
                ?? CGRect(x: 0, y: 0, width: side, height: side)
            bodies[presence.spritePackName] = ink
        }
        return ink.offsetBy(dx: center.x - side / 2, dy: center.y - side / 2)
    }

    private func take(_ hit: ShooHit, presence: PetPresence, center: CGPoint, now: TimeInterval) {
        presence.shooNextHitAt = now + PetShooDirector.hitCooldownInSeconds
        presence.shooStaysAwayUntil = now + PetShooDirector.staysAwayInSeconds
        if presence.shooFlight != nil {
            presence.shooFlight?.take(hit)
            return
        }
        presence.groundBody = nil
        presence.shooFlight = ShooFlight(from: center, hit: hit, facingLeft: hit.velocity.dx < 0)
        presence.view.update(spaceRotationInRadians: 0)
    }

    private func fly(_ presence: PetPresence, elapsedSeconds: Double, now: TimeInterval, stage: ShooStage) -> ShooOrder {
        guard var flight = presence.shooFlight else { return .free }
        let aboveFeet = PetShooDirector.spriteCenterAboveFeet(presence)
        let halfSprite = presence.view.petAppearance.spriteSideLength / 2
        flight.advance(
            elapsedSeconds: elapsedSeconds,
            walls: centerRange(of: presence, stage: stage),
            ceiling: stage.visibleFrame.maxY - halfSprite,
            floorAt: { x in stage.floorUnder(presence, x) + aboveFeet }
        )
        presence.shooFlight = flight
        presence.groundBody = nil
        if flight.hasLanded {
            presence.shooStaysAwayUntil = now + PetShooDirector.staysAwayInSeconds
            leaveFlight(presence)
            return .landed
        }
        presence.animator.advanceInSpace(elapsedSeconds: elapsedSeconds)
        presence.view.update(spaceRotationInRadians: CGFloat(flight.rotationInRadians))
        place(presence, flight: flight)
        return .flying
    }

    /// The view turns around its content's center, and the sprite sits below that, so the
    /// window moves as the pet turns to keep the turn around the sprite's own middle.
    private func place(_ presence: PetPresence, flight: ShooFlight) {
        let size = presence.view.preferredSize
        let lever = PetShooDirector.spriteCenterAboveFeet(presence) - presence.view.contentSize.height / 2
        let angle = flight.rotationInRadians
        let windowCenter = CGPoint(
            x: flight.center.x + lever * CGFloat(sin(angle)),
            y: flight.center.y - lever * CGFloat(cos(angle))
        )
        let frame = CGRect(
            x: (windowCenter.x - size.width / 2).rounded(),
            y: (windowCenter.y - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
        guard frame != presence.window.frame else { return }
        presence.window.setFrame(frame, display: false)
    }

    private func shoveFloating(
        _ presence: PetPresence,
        contact: ShooContact,
        center: CGPoint,
        elapsedSeconds: Double,
        now: TimeInterval,
        stage: ShooStage
    ) -> ShooOrder {
        let side = roomierSide(at: center.x, stage: stage)
        switch contact {
        case .touch(let point):
            let hit = ShooImpulse.jolt(at: point, center: center, cursorVelocity: cursorVelocity, grounded: false, roomierSide: side)
            presence.spaceMotion?.shove(by: hit.velocity)
            presence.shooNextHitAt = now + PetShooDirector.hitCooldownInSeconds
        case .deep(let point):
            let hit = ShooImpulse.launch(at: point, center: center, cursorVelocity: cursorVelocity, roomierSide: side)
            presence.spaceMotion?.shove(by: hit.velocity)
            presence.shooNextHitAt = now + PetShooDirector.hitCooldownInSeconds
        case .near(let gap):
            if let cursor {
                presence.spaceMotion?.shove(by: ShooRun.airPush(from: cursor, center: center, gap: gap, elapsedSeconds: elapsedSeconds))
            }
        case .clear:
            break
        }
        return .free
    }

    private func centerRange(of presence: PetPresence, stage: ShooStage) -> ClosedRange<CGFloat> {
        let halfWidth = presence.view.contentSize.width / 2
        let low = stage.visibleFrame.minX + halfWidth
        let high = stage.visibleFrame.maxX - halfWidth
        return min(low, high)...max(low, high)
    }

    private func offsetRange(of presence: PetPresence, stage: ShooStage) -> ClosedRange<CGFloat> {
        let centers = centerRange(of: presence, stage: stage)
        return (centers.lowerBound - presence.homeHorizontalCenter)...(centers.upperBound - presence.homeHorizontalCenter)
    }

    private func roomierSide(at x: CGFloat, stage: ShooStage) -> CGFloat {
        x <= stage.visibleFrame.midX ? 1 : -1
    }
}
