import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import AgentPetCore
@testable import agent_pet

private let tick = 1.0 / 30.0
private let body = CGRect(x: 400, y: 100, width: 40, height: 50)
private let center = CGPoint(x: 420, y: 125)

@Suite("Shift counts only when it was not typing")
struct ShooArmingTests {
    private func armed(after seconds: Double, sinceKey: (Double) -> Double) -> Bool {
        var arming = ShooArming()
        var held = 0.0
        var result = arming.update(shiftIsAlone: true, secondsSinceKeyDown: sinceKey(held), elapsedSeconds: tick)
        while held < seconds {
            held += tick
            result = arming.update(shiftIsAlone: true, secondsSinceKeyDown: sinceKey(held), elapsedSeconds: tick)
        }
        return result
    }

    @Test func aHeldShiftArmsAfterAMoment() {
        #expect(!armed(after: 0.05) { held in 10 + held })
        #expect(armed(after: 0.2) { held in 10 + held })
    }

    @Test func aCapitalLetterNeverArmsIt() {
        // Shift goes down, the letter 50 ms later, and Shift stays down a little longer.
        #expect(!armed(after: 0.6) { held in held < 0.05 ? 10 + held : held - 0.05 })
    }

    @Test func typingJustBeforeShiftKeepsItQuiet() {
        #expect(!armed(after: 0.15) { held in 0.1 + held })
        #expect(armed(after: 0.3) { held in 0.1 + held })
    }

    @Test func anotherModifierOrALetGoEndsIt() {
        var arming = ShooArming()
        for _ in 0..<10 { arming.update(shiftIsAlone: true, secondsSinceKeyDown: 10, elapsedSeconds: tick) }
        #expect(arming.isArmed)
        let afterLetGo = arming.update(shiftIsAlone: false, secondsSinceKeyDown: 10, elapsedSeconds: tick)
        #expect(!afterLetGo)
    }
}

@Suite("how far the cursor got into a pet")
struct ShooReachTests {
    @Test func farAwayIsClear() {
        let point = CGPoint(x: 700, y: 400)
        #expect(ShooReach.contact(from: point, to: point, body: body) == .clear)
    }

    @Test func closeByIsNearWithItsGap() {
        let point = CGPoint(x: 370, y: 125)
        #expect(ShooReach.contact(from: point, to: point, body: body) == .near(gap: 30))
    }

    @Test func theEdgeIsATouchAndTheMiddleIsDeep() {
        let edge = CGPoint(x: 402, y: 125)
        #expect(ShooReach.contact(from: edge, to: edge, body: body) == .touch(at: edge))
        #expect(ShooReach.contact(from: center, to: center, body: body) == .deep(at: center))
    }

    @Test func aFastCursorCannotPassThroughUnnoticed() {
        let through = ShooReach.contact(from: CGPoint(x: 300, y: 125), to: CGPoint(x: 600, y: 125), body: body)
        guard case .deep = through else {
            Issue.record("expected deep, got \(through)")
            return
        }
        let clipped = ShooReach.contact(from: CGPoint(x: 395, y: 90), to: CGPoint(x: 410, y: 105), body: body)
        #expect(clipped == .touch(at: CGPoint(x: 410, y: 105)))
        let corner = ShooReach.contact(from: CGPoint(x: 380, y: 110), to: CGPoint(x: 420, y: 90), body: body)
        #expect(corner == .touch(at: CGPoint(x: 400, y: 100)))
    }
}

@Suite("where a hit sends the pet")
struct ShooImpulseTests {
    private let still = CGVector(dx: 0, dy: 0)

    @Test func aJoltGoesAwayFromTheHitSide() {
        let fromLeft = ShooImpulse.jolt(at: CGPoint(x: 400, y: 125), center: center, cursorVelocity: still, grounded: true, roomierSide: 1)
        #expect(fromLeft.velocity.dx > 0)
        #expect(fromLeft.velocity.dy >= ShooImpulse.joltMinimumLift)
        let fromRight = ShooImpulse.jolt(at: CGPoint(x: 440, y: 125), center: center, cursorVelocity: still, grounded: true, roomierSide: 1)
        #expect(fromRight.velocity.dx < 0)
    }

    @Test func aFasterCursorHitsHarderUpToTheLimit() {
        let point = CGPoint(x: 400, y: 125)
        let gentle = ShooImpulse.jolt(at: point, center: center, cursorVelocity: CGVector(dx: 100, dy: 0), grounded: false, roomierSide: 1)
        let hard = ShooImpulse.jolt(at: point, center: center, cursorVelocity: CGVector(dx: 1200, dy: 0), grounded: false, roomierSide: 1)
        #expect(hard.velocity.dx > gentle.velocity.dx)
        let wild = ShooImpulse.jolt(at: point, center: center, cursorVelocity: CGVector(dx: 90000, dy: 0), grounded: false, roomierSide: 1)
        #expect(abs(wild.velocity.dx) < 20000)
    }

    @Test func hitFromAboveOnTheGroundBouncesUpAndSideways() {
        let hit = ShooImpulse.jolt(at: CGPoint(x: 420, y: 150), center: center, cursorVelocity: CGVector(dx: 0, dy: -800), grounded: true, roomierSide: -1)
        #expect(hit.velocity.dy > 0)
        #expect(hit.velocity.dx <= -ShooImpulse.joltMinimumSideways)
    }

    @Test func offCenterHitsTurnThePetTheWayThePushWould() {
        let rightSideGoingUp = ShooImpulse.jolt(at: CGPoint(x: 440, y: 125), center: center, cursorVelocity: CGVector(dx: 0, dy: 1500), grounded: false, roomierSide: 1)
        let rightSideGoingDown = ShooImpulse.jolt(at: CGPoint(x: 440, y: 125), center: center, cursorVelocity: CGVector(dx: 0, dy: -1500), grounded: false, roomierSide: 1)
        #expect(rightSideGoingUp.spinRadiansPerSecond > rightSideGoingDown.spinRadiansPerSecond)
    }

    @Test func aLaunchIsFasterThanAJoltAndNeverGoesDownOrStraightUp() {
        for contact in [CGPoint(x: 420, y: 150), CGPoint(x: 420, y: 100), center, CGPoint(x: 405, y: 125)] {
            for side: CGFloat in [-1, 1] {
                let hit = ShooImpulse.launch(at: contact, center: center, cursorVelocity: still, roomierSide: side)
                let speed = hypot(hit.velocity.dx, hit.velocity.dy)
                #expect(speed >= ShooImpulse.launchBaseSpeed - 0.001)
                #expect(hit.velocity.dy / speed >= ShooImpulse.launchLowestElevation - 0.001)
                #expect(abs(hit.velocity.dx) / speed >= ShooImpulse.launchLeastSideways - 0.001)
            }
        }
    }
}

@Suite("a shooed pet in the air")
struct ShooFlightTests {
    private let walls: ClosedRange<CGFloat> = 50...1400
    private let ceiling: CGFloat = 860
    private let groundLevel: CGFloat = 40

    private func flight(_ velocity: CGVector, spin: Double = 8, at start: CGPoint = CGPoint(x: 700, y: 40)) -> ShooFlight {
        ShooFlight(from: start, hit: ShooHit(velocity: velocity, spinRadiansPerSecond: spin), facingLeft: false)
    }

    @Test func aLaunchBouncesAroundInsideTheScreenAndLandsUpright() {
        var motion = flight(CGVector(dx: 1900, dy: 1600))
        var seconds = 0.0
        var touchedWall = false
        while !motion.hasLanded, seconds < 30 {
            motion.advance(elapsedSeconds: tick, walls: walls, ceiling: ceiling) { _ in groundLevel }
            seconds += tick
            #expect(walls.contains(motion.center.x))
            #expect(motion.center.y <= ceiling && motion.center.y >= groundLevel)
            if motion.center.x == walls.upperBound { touchedWall = true }
        }
        #expect(motion.hasLanded)
        #expect(touchedWall)
        #expect(motion.rotationInRadians == 0)
        #expect(motion.center.y == groundLevel)
        #expect(seconds < 10)
    }

    @Test func itKeepsMovingTheWayItWasHitUntilAWall() {
        var motion = flight(CGVector(dx: -500, dy: 400))
        motion.advance(elapsedSeconds: 0.2, walls: walls, ceiling: ceiling) { _ in groundLevel }
        #expect(motion.center.x < 700)
        #expect(motion.center.y > groundLevel)
    }

    @Test func theEndOfTheDockStopsALowFlightLikeAWall() {
        let dockFloor: (CGFloat) -> CGFloat = { x in x > 800 ? 110 : 40 }
        var motion = flight(CGVector(dx: 900, dy: 150))
        for _ in 0..<12 {
            motion.advance(elapsedSeconds: tick, walls: walls, ceiling: ceiling, floorAt: dockFloor)
            #expect(motion.center.y >= dockFloor(motion.center.x))
        }
        #expect(motion.center.x <= 800)
        #expect(motion.velocity.dx < 0)
    }

    @Test func aHitInTheAirChangesItsCourse() {
        var motion = flight(CGVector(dx: 400, dy: 400))
        motion.take(ShooHit(velocity: CGVector(dx: -900, dy: 300), spinRadiansPerSecond: 1))
        #expect(motion.velocity.dx == -900)
        #expect(motion.spinRadiansPerSecond == 1)
    }

    @Test func aLargeStepIsStillSafe() {
        var motion = flight(CGVector(dx: 3000, dy: 3000))
        motion.advance(elapsedSeconds: 0.25, walls: walls, ceiling: ceiling) { _ in groundLevel }
        #expect(walls.contains(motion.center.x))
        #expect(motion.center.y <= ceiling)
    }
}

@Suite("running from the cursor")
struct ShooRunTests {
    @Test func closerIsFaster() {
        #expect(ShooRun.speed(gap: 0) == ShooRun.fastestSpeed)
        #expect(ShooRun.speed(gap: ShooReach.nearRadius) == ShooRun.slowestSpeed)
        #expect(ShooRun.speed(gap: 10) > ShooRun.speed(gap: 50))
    }

    @Test func itRunsAwayAndTowardRoomWhenDirectlyUnder() {
        #expect(ShooRun.direction(petX: 500, cursorX: 400, roomierSide: -1) == 1)
        #expect(ShooRun.direction(petX: 300, cursorX: 400, roomierSide: 1) == -1)
        #expect(ShooRun.direction(petX: 400, cursorX: 401, roomierSide: -1) == -1)
    }

    @Test func theDrawnPartOfAFrameIsTheBody() {
        let frame = PixelFrame([
            "....",
            ".##.",
            ".#..",
            "...."
        ])
        #expect(frame.inkBounds(sideLengthInPoints: 40) == CGRect(x: 10, y: 10, width: 20, height: 20))
        #expect(PixelFrame(["..", ".."]).inkBounds(sideLengthInPoints: 16) == CGRect(x: 0, y: 0, width: 16, height: 16))
    }
}

private final class FakeShooInput: ShooInputSource {
    var cursor = CGPoint(x: 1200, y: 800)
    var shift = true
    var sinceKey = 100.0

    func sample() -> ShooInput {
        ShooInput(cursor: cursor, shiftIsHeld: shift, shiftIsAlone: shift, secondsSinceKeyDown: sinceKey)
    }
}

@Suite("the director tells each pet what to do")
@MainActor
struct PetShooDirectorTests {
    private let stage = ShooStage(visibleFrame: CGRect(x: 0, y: 0, width: 1500, height: 900)) { _, _ in 0 }

    private func presence() -> (PetPresence, FakePetWindow) {
        let view = PetView(
            sessionId: "shoo",
            petAppearance: PetAppearance(
                label: "shoo", accent: .cyan, mood: .ready, message: nil, bubbleCaption: nil,
                labelPlacement: .nametag, spriteSideLength: 64, feetFlush: true
            )
        )
        let size = view.preferredSize
        let window = FakePetWindow(frame: CGRect(x: 700 - size.width / 2, y: 0, width: size.width, height: size.height))
        let presence = PetPresence(
            sessionId: "shoo", window: window, view: view,
            spritePackName: "claude", spriteSheet: SpriteSheet.claude8Bit
        )
        presence.homeHorizontalCenter = 700
        for _ in 0..<40 { presence.animator.advance(elapsedSeconds: tick, mood: .ready) }
        presence.animator.stand(atHorizontalOffsetFromHome: 0)
        return (presence, window)
    }

    private func armedDirector(_ input: FakeShooInput) -> PetShooDirector {
        let director = PetShooDirector(input: input)
        for _ in 0..<6 { director.beginTick(enabled: true, elapsedSeconds: tick) }
        return director
    }

    @Test func aPetNearTheCursorRunsAway() {
        let (pet, window) = presence()
        let input = FakeShooInput()
        input.cursor = CGPoint(x: window.frame.midX - 70, y: 30)
        let director = armedDirector(input)
        let order = director.advance(pet, elapsedSeconds: tick, now: 0, stage: stage)
        guard case .flee(let direction, let speed, let range) = order else {
            Issue.record("expected flee, got \(order)")
            return
        }
        #expect(direction == 1)
        #expect(speed > ShooRun.slowestSpeed)
        #expect(range.contains(0))
        pet.animator.flee(elapsedSeconds: tick, direction: direction, speed: speed, within: range) { _ in true }
        #expect(pet.animator.horizontalOffsetFromHome > 0)
        #expect(pet.animator.animationName == .walk)
    }

    @Test func runningStopsAtTheEdgeOfTheScreen() {
        let (pet, _) = presence()
        pet.animator.flee(elapsedSeconds: 10, direction: 1, speed: 400, within: -100...50) { _ in true }
        #expect(pet.animator.horizontalOffsetFromHome == 50)
    }

    @Test func aTouchKnocksItAwayFromTheHitSideAndItComesDownAndStaysAway() {
        let (pet, window) = presence()
        let input = FakeShooInput()
        let inkEdge = window.frame.midX - 32 + SpriteSheet.claude8Bit.idle[0].inkBounds(sideLengthInPoints: 64).minX
        input.cursor = CGPoint(x: inkEdge + 1, y: 25)
        let director = armedDirector(input)
        #expect(director.advance(pet, elapsedSeconds: tick, now: 0, stage: stage) == .flying)
        #expect((pet.shooFlight?.velocity.dx ?? 0) > 0)
        #expect(pet.isInFlight)
        #expect(director.keepsClicksOff(pet))
        #expect(pet.view.spaceRotationInRadians != nil)

        input.cursor = CGPoint(x: 1400, y: 800)
        input.shift = false
        var now = tick
        var order = ShooOrder.flying
        while order == .flying, now < 15 {
            director.beginTick(enabled: true, elapsedSeconds: tick)
            order = director.advance(pet, elapsedSeconds: tick, now: now, stage: stage)
            now += tick
        }
        #expect(order == .landed)
        #expect(pet.shooFlight == nil)
        #expect(pet.view.spaceRotationInRadians == nil)
        #expect(pet.animator.horizontalOffsetFromHome > 0)
        director.beginTick(enabled: true, elapsedSeconds: tick)
        #expect(director.advance(pet, elapsedSeconds: tick, now: now, stage: stage) == .stayPut)
        director.beginTick(enabled: true, elapsedSeconds: tick)
        #expect(director.advance(pet, elapsedSeconds: tick, now: now + PetShooDirector.staysAwayInSeconds + 1, stage: stage) == .free)
    }

    @Test func theSpriteTurnsAroundItsOwnMiddle() {
        let (pet, window) = presence()
        let input = FakeShooInput()
        let start = CGPoint(x: window.frame.midX, y: 32)
        input.cursor = start
        let director = armedDirector(input)
        #expect(director.advance(pet, elapsedSeconds: tick, now: 0, stage: stage) == .flying)
        let flight = pet.shooFlight!
        let lever = 32 - pet.view.contentSize.height / 2
        let expectedX = flight.center.x + lever * CGFloat(sin(flight.rotationInRadians))
        let expectedY = flight.center.y - lever * CGFloat(cos(flight.rotationInRadians))
        #expect(abs(window.frame.midX - expectedX) <= 1)
        #expect(abs(window.frame.midY - expectedY) <= 1)
    }

    @Test func deepInsideLaunchesItFarHigherThanATouch() {
        let (pet, window) = presence()
        let input = FakeShooInput()
        input.cursor = CGPoint(x: window.frame.midX, y: 32)
        let director = armedDirector(input)
        _ = director.advance(pet, elapsedSeconds: tick, now: 0, stage: stage)
        let speed = hypot(pet.shooFlight!.velocity.dx, pet.shooFlight!.velocity.dy)
        #expect(speed > ShooImpulse.launchBaseSpeed - 100)
    }

    @Test func aDivingPetDropsOutOfTheFlight() {
        let (pet, window) = presence()
        let input = FakeShooInput()
        input.cursor = CGPoint(x: window.frame.midX, y: 32)
        let director = armedDirector(input)
        _ = director.advance(pet, elapsedSeconds: tick, now: 0, stage: stage)
        pet.animator.requestDive()
        #expect(director.advance(pet, elapsedSeconds: tick, now: tick, stage: stage) == .free)
        #expect(pet.shooFlight == nil)
        #expect(pet.view.spaceRotationInRadians == nil)
    }

    @Test func nothingHappensWithItOff() {
        let (pet, window) = presence()
        let input = FakeShooInput()
        input.cursor = CGPoint(x: window.frame.midX, y: 32)
        let director = PetShooDirector(input: input)
        for _ in 0..<6 { director.beginTick(enabled: false, elapsedSeconds: tick) }
        #expect(director.advance(pet, elapsedSeconds: tick, now: 0, stage: stage) == .free)
        #expect(!director.keepsClicksOff(pet))
    }

    @Test func clicksGoThroughWhileShiftIsDownEvenBeforeItArms() {
        let (pet, _) = presence()
        let director = PetShooDirector(input: FakeShooInput())
        director.beginTick(enabled: true, elapsedSeconds: tick)
        #expect(director.keepsClicksOff(pet))
    }

    @Test func aFloatingPetTakesTheHitAsSpeed() {
        let (pet, window) = presence()
        pet.spaceMotion = SpaceMotion(launchingFrom: CGPoint(x: window.frame.midX, y: 32), seed: 3)
        let before = pet.spaceMotion!.velocity
        let input = FakeShooInput()
        input.cursor = CGPoint(x: window.frame.midX, y: 32)
        let director = armedDirector(input)
        #expect(director.advance(pet, elapsedSeconds: tick, now: 0, stage: stage) == .free)
        #expect(pet.shooFlight == nil)
        #expect(hypot(pet.spaceMotion!.velocity.dx, pet.spaceMotion!.velocity.dy) > hypot(before.dx, before.dy))
    }
}

@Suite("the menu bar icon's switches")
struct PetMenuBarSettingsTests {
    @Test func theyRoundTripAndDefaultToOpeningAtLogin() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("menu-bar-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(PetMenuBarSettings.load(from: file) == PetMenuBarSettings(hidesPets: false, opensAtLogin: true))
        #expect(PetMenuBarSettings(hidesPets: true, opensAtLogin: false).save(to: file))
        #expect(PetMenuBarSettings.load(from: file) == PetMenuBarSettings(hidesPets: true, opensAtLogin: false))
        try Data("{\"hidesPets\": 3}".utf8).write(to: file)
        #expect(PetMenuBarSettings.load(from: file) == PetMenuBarSettings())
    }

    @Test func loginStartIsOnlyTurnedOffWithTheIconOn() {
        var configuration = AgentPetConfiguration.defaults
        let off = PetMenuBarSettings(opensAtLogin: false)
        #expect(!PetLoginItem.isTurnedOff(configuration: { configuration }, settings: { off }))
        configuration.showsMenuBarIcon = true
        #expect(PetLoginItem.isTurnedOff(configuration: { configuration }, settings: { off }))
        #expect(!PetLoginItem.isTurnedOff(configuration: { configuration }, settings: { PetMenuBarSettings() }))
    }

    @Test func aHookStartsTheDaemonItselfWhileLoginStartIsOff() {
        var spawned = false
        var kicked = false
        let start = DaemonCommand.ensureRunningOnItsOwn(using: DaemonCommand.Starter(
            homeIsForeign: { false },
            launchAgentIsInstalled: { false },
            startLaunchAgent: { kicked = true },
            runningDaemon: { nil },
            parentOf: { _ in nil },
            spawnDetached: { spawned = true; return true }
        ))
        #expect(start == .spawnedOnItsOwn)
        #expect(spawned)
        #expect(!kicked)
    }

    @Test func theIconIsATemplateOfTheEmergingPet() {
        #expect(PetMenuBar.iconRows.count == 16)
        #expect(PetMenuBar.iconRows.allSatisfy { row in row.count == 16 })
        #expect(PetMenuBar.iconImage().isTemplate)
    }

    @Test func theConfigKeysAreOffByDefaultAndReadWhenSet() {
        #expect(!AgentPetConfiguration.defaults.shiftShoos)
        #expect(!AgentPetConfiguration.defaults.showsMenuBarIcon)
        let parsed = ConfigurationFile.parse(Data("{\"shiftShoo\": true, \"menuBarIcon\": true}".utf8))
        #expect(parsed.shiftShoos)
        #expect(parsed.showsMenuBarIcon)
    }
}
