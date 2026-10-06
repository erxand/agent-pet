import CoreGraphics
import Foundation
import Testing
@testable import AgentPetCore

@Suite("screensaver config")
struct ScreensaverConfigurationTests {
    private func parse(_ json: String) -> AgentPetConfiguration {
        ConfigurationFile.parse(Data(json.utf8))
    }

    @Test func floatingIsOffAndTheParamifyScreensaverIsWatchedByDefault() {
        #expect(!AgentPetConfiguration.defaults.floatsOverScreensaver)
        #expect(!AgentPetConfiguration.defaults.simulatesScreensaver)
        #expect(AgentPetConfiguration.defaults.screensaverBundleIdentifiers == ["com.paramify.screensaver"])
    }

    @Test func theKeysAreRead() {
        let configuration = parse(#"{"floatOverScreensaver":true,"screensaverBundleIds":["com.example.saver",3,""],"simulateScreensaver":true}"#)
        #expect(configuration.floatsOverScreensaver)
        #expect(configuration.simulatesScreensaver)
        #expect(configuration.screensaverBundleIdentifiers == ["com.example.saver"])
    }

    @Test func anEmptyListWatchesNothingAndBadValuesAreTheDefaults() {
        #expect(parse(#"{"screensaverBundleIds":[]}"#).screensaverBundleIdentifiers.isEmpty)
        #expect(parse(#"{"floatOverScreensaver":"yes","screensaverBundleIds":"com.example.saver"}"#) == .defaults)
    }
}

@Suite("screensaver detection")
struct ScreensaverDetectionTests {
    private static let saverProcess: Int32 = 1733
    private static let otherProcess: Int32 = 42
    private static let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private static let secondDisplay = CGRect(x: 1728, y: -200, width: 2560, height: 1440)

    private func window(
        owner: Int32 = ScreensaverDetectionTests.saverProcess,
        bounds: CGRect = ScreensaverDetectionTests.display,
        level: Int = 1000,
        alpha: Double = 1,
        isOnScreen: Bool = true
    ) -> ScreensaverWindow {
        ScreensaverWindow(ownerProcessIdentifier: owner, bounds: bounds, level: level, alpha: alpha, isOnScreen: isOnScreen)
    }

    private func cover(_ windows: [ScreensaverWindow]) -> ScreensaverCover? {
        ScreensaverDetection.cover(
            windows: windows,
            ownerProcessIdentifiers: [ScreensaverDetectionTests.saverProcess],
            displayBounds: [ScreensaverDetectionTests.display, ScreensaverDetectionTests.secondDisplay]
        )
    }

    @Test func aFullScreenWindowOfTheScreensaverIsACover() {
        #expect(cover([window()]) == ScreensaverCover(windowLevel: 1000))
        #expect(cover([window(bounds: ScreensaverDetectionTests.secondDisplay, level: 1001)]) == ScreensaverCover(windowLevel: 1001))
    }

    @Test func theHighestCoveringLevelWins() {
        #expect(cover([window(level: 25), window(bounds: ScreensaverDetectionTests.secondDisplay, level: 1002)])?.windowLevel == 1002)
    }

    @Test func smallHiddenTransparentOrForeignWindowsAreNotACover() {
        #expect(cover([]) == nil)
        #expect(cover([window(bounds: CGRect(x: 0, y: 0, width: 400, height: 300))]) == nil)
        #expect(cover([window(bounds: CGRect(x: 0, y: 0, width: 1728, height: 900))]) == nil)
        #expect(cover([window(alpha: 0)]) == nil)
        #expect(cover([window(isOnScreen: false)]) == nil)
        #expect(cover([window(owner: ScreensaverDetectionTests.otherProcess)]) == nil)
    }

    @Test func theResponseFollowsTheFloatKey() {
        let up = ScreensaverCover(windowLevel: 1000)
        #expect(ScreensaverDetection.response(to: nil, floatsOverScreensaver: true) == .none)
        #expect(ScreensaverDetection.response(to: nil, floatsOverScreensaver: false) == .none)
        #expect(ScreensaverDetection.response(to: up, floatsOverScreensaver: false) == .hidePets)
        #expect(ScreensaverDetection.response(to: up, floatsOverScreensaver: true) == .floatPets(levelAbove: 1000))
    }

    @Test func floatingPetsGoJustAboveTheScreensaverAndNeverAboveTheShieldingLevel() {
        let shielding = 2_147_483_628
        #expect(ScreensaverDetection.floatingPetLevel(screensaverLevel: 1000, petLevel: 1000, shieldingLevel: shielding) == 1001)
        #expect(ScreensaverDetection.floatingPetLevel(screensaverLevel: 25, petLevel: 1000, shieldingLevel: shielding) == 1000)
        #expect(ScreensaverDetection.floatingPetLevel(screensaverLevel: shielding, petLevel: 1000, shieldingLevel: shielding) == shielding - 1)
    }
}

@Suite("pets in space")
struct SpaceMotionTests {
    private static let tick = 1.0 / 30.0
    private static let area = SpaceArea(
        lowestCenter: CGPoint(x: 60, y: 50),
        highestCenter: CGPoint(x: 1380, y: 840)
    )
    private static let launch = CGPoint(x: 400, y: 50)

    private func run(_ motion: inout SpaceMotion, seconds: Double, home: CGFloat = 700, each: (SpaceMotion) -> Void = { _ in }) {
        var elapsed = 0.0
        while elapsed < seconds {
            motion.advance(elapsedSeconds: SpaceMotionTests.tick, area: SpaceMotionTests.area, homeCenterX: home)
            each(motion)
            elapsed += SpaceMotionTests.tick
        }
    }

    @Test func theSameSeedFloatsTheSameWayAndAnotherSeedDoesNot() {
        var first = SpaceMotion(launchingFrom: SpaceMotionTests.launch, seed: SpaceMotion.seed(forPetKey: "pet-a"))
        var second = SpaceMotion(launchingFrom: SpaceMotionTests.launch, seed: SpaceMotion.seed(forPetKey: "pet-a"))
        var other = SpaceMotion(launchingFrom: SpaceMotionTests.launch, seed: SpaceMotion.seed(forPetKey: "pet-b"))
        run(&first, seconds: 10)
        run(&second, seconds: 10)
        run(&other, seconds: 10)
        #expect(first == second)
        #expect(first != other)
    }

    @Test func aFloatingPetLiftsOffDriftsSlowlyAndSpinsAndNeverLeavesTheScreen() {
        for petIndex in 0..<20 {
            var motion = SpaceMotion(launchingFrom: SpaceMotionTests.launch, seed: SpaceMotion.seed(forPetKey: "pet-\(petIndex)"))
            #expect(motion.velocity.dy > 0)
            let speed = hypot(motion.velocity.dx, motion.velocity.dy)
            #expect(speed >= SpaceMotion.minimumDriftSpeed - 0.001 && speed <= SpaceMotion.maximumDriftSpeed + 0.001)
            #expect(abs(motion.spinRadiansPerSecond) >= SpaceMotion.minimumSpinRadiansPerSecond)
            #expect(abs(motion.spinRadiansPerSecond) <= SpaceMotion.maximumSpinRadiansPerSecond)
            var rotations: Set<Int> = []
            run(&motion, seconds: 120) { step in
                #expect(SpaceMotionTests.area.contains(step.center))
                #expect(step.phase == .floating)
                rotations.insert(Int(step.rotationInRadians * 10))
            }
            #expect(rotations.count > 10)
            #expect(motion.center.y > SpaceMotionTests.area.groundCenterY)
        }
    }

    @Test func whenTheScreensaverGoesThePetFallsLandsUprightAndWalksHome() {
        var motion = SpaceMotion(launchingFrom: SpaceMotionTests.launch, seed: SpaceMotion.seed(forPetKey: "pet-fall"))
        run(&motion, seconds: 8)
        motion.returnToGround()
        #expect(motion.phase == .falling)
        var lastHeight = motion.center.y
        var fallSeconds = 0.0
        while motion.phase == .falling {
            run(&motion, seconds: SpaceMotionTests.tick)
            #expect(motion.center.y <= lastHeight + 2)
            lastHeight = motion.center.y
            fallSeconds += SpaceMotionTests.tick
            #expect(fallSeconds < 3)
        }
        #expect(motion.phase == .walkingHome)
        #expect(motion.center.y == SpaceMotionTests.area.groundCenterY)
        #expect(motion.rotationInRadians == 0)
        #expect(motion.animationName == .walk)
        #expect(motion.facingLeft == (motion.center.x > 700))
        let distance = abs(motion.center.x - 700)
        var walkSeconds = 0.0
        while motion.phase == .walkingHome {
            run(&motion, seconds: SpaceMotionTests.tick)
            #expect(motion.center.y == SpaceMotionTests.area.groundCenterY)
            walkSeconds += SpaceMotionTests.tick
        }
        #expect(motion.phase == .home)
        #expect(motion.center.x == 700)
        #expect(walkSeconds <= Double(distance / SpaceMotion.walkSpeedInPointsPerSecond) + 0.1)
    }

    @Test func returningToGroundIsIdempotentAndHomeIsFinal() {
        var motion = SpaceMotion(launchingFrom: SpaceMotionTests.launch, seed: 7)
        motion.returnToGround()
        motion.returnToGround()
        #expect(motion.phase == .falling)
        run(&motion, seconds: 60)
        #expect(motion.phase == .home)
        motion.returnToGround()
        #expect(motion.phase == .home)
    }

    @Test func turningUprightTakesTheShortWay() {
        #expect(SpaceMotion.turnedTowardUpright(0.5, byAtMost: 0.2) == 0.3)
        #expect(abs(SpaceMotion.turnedTowardUpright(-0.5, byAtMost: 0.2) + 0.3) < 0.000_001)
        #expect(SpaceMotion.turnedTowardUpright(0.1, byAtMost: 0.2) == 0)
        let nearlyFullTurn = Double.pi * 2 - 0.5
        #expect(abs(SpaceMotion.turnedTowardUpright(nearlyFullTurn, byAtMost: 0.2) + 0.3) < 0.000_001)
    }
}

@Suite("rescans only on change")
struct RescanTests {
    @Test func theGateRescansOnAChangeWhenForcedAndOnTheFallbackInterval() {
        var gate = RescanGate(fallbackIntervalInSeconds: 5)
        let calls: [(changed: Bool, forced: Bool, now: TimeInterval, expected: Bool)] = [
            (false, false, 100, true),
            (false, false, 100.3, false),
            (false, false, 104.9, false),
            (true, false, 105, true),
            (false, false, 109.9, false),
            (false, true, 110, true),
            (false, false, 115, true)
        ]
        for call in calls {
            let rescans = gate.shouldRescan(changeReported: call.changed, forced: call.forced, now: call.now)
            #expect(rescans == call.expected, "at \(call.now)")
        }
    }

    @Test func theMonitorReportsAFileWrittenInAWatchedFolderOnce() async throws {
        let directory = try TemporaryDirectory()
        let packs = try directory.makeDirectory("sprites/golem")
        let monitor = DirectoryChangeMonitor()
        monitor.watch(directories: [directory.url.appendingPathComponent("sprites", isDirectory: true)])
        #expect(monitor.isWatching)
        try await Task.sleep(nanoseconds: 300_000_000)
        _ = monitor.consumeChange()
        try "{}".write(to: packs.appendingPathComponent("pack.json"), atomically: false, encoding: .utf8)
        var reported = false
        for _ in 0..<60 where !reported {
            try await Task.sleep(nanoseconds: 50_000_000)
            reported = monitor.consumeChange()
        }
        #expect(reported)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(!monitor.consumeChange())
    }

    @Test func watchingTheSameFoldersAgainKeepsTheStreamAndNoFoldersStopsIt() throws {
        let directory = try TemporaryDirectory()
        let monitor = DirectoryChangeMonitor()
        monitor.watch(directories: [directory.url, directory.url])
        #expect(monitor.watchedPaths == [directory.url.standardizedFileURL.path])
        monitor.watch(directories: [directory.url])
        #expect(monitor.isWatching)
        monitor.watch(directories: [])
        #expect(!monitor.isWatching)
    }
}
