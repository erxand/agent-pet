import CoreGraphics
import Foundation
import Testing
@testable import AgentPetCore

@Suite("pet states")
struct PetStateTests {
    private func parse(_ json: String) -> AgentPetConfiguration {
        ConfigurationFile.parse(Data(json.utf8))
    }

    @Test func noConfigAndNoCommandIsTheDefaultsWithNoRules() {
        #expect(AgentPetConfiguration.defaults.fullScreenRules.isEmpty)
        let states = PetEffectiveStates.resolve(commands: .none, trigger: .none)
        #expect(states == .defaults)
        #expect(states.physics == .ground && states.input == .on && states.visibility == .shown && states.level == .normal)
        #expect(PetStateKind.allCases.allSatisfy { kind in states.source(of: kind) == .defaultValue })
    }

    @Test func aRuleIsReadAndBadRulesAreDropped() {
        let configuration = parse(#"""
        {"whenFullScreen": [
          {"bundleIds": ["com.example.saver", 3, ""], "apply": {"physics": "float", "input": "off", "level": "above"}},
          {"bundleIds": [], "apply": {"physics": "float"}},
          {"bundleIds": ["com.example.other"], "apply": {"physics": "sideways"}},
          {"bundleIds": ["com.example.other"]},
          "not a rule"
        ]}
        """#)
        #expect(configuration.fullScreenRules == [
            PetFullScreenRule(bundleIdentifiers: ["com.example.saver"], physics: .float, input: .off, level: .above)
        ])
        #expect(parse(#"{"whenFullScreen": "com.example.saver"}"#) == .defaults)
    }

    @Test func aRuleAppliesOnlyWhileItsAppCoversADisplayAndLevelAboveNamesThatApp() {
        let rules = [PetFullScreenRule(bundleIdentifiers: ["com.example.saver"], physics: .float, input: .off, level: .above)]
        let covering = ["com.example.saver": AppWindowSummary(coversDisplay: true, topLevel: 1000)]
        let small = ["com.example.saver": AppWindowSummary(coversDisplay: false, topLevel: 1000)]
        #expect(PetFullScreenRule.triggered(by: rules, summaries: covering) == PetStateSettings(
            physics: .float,
            input: .off,
            level: .above(bundleIdentifier: "com.example.saver")
        ))
        #expect(PetFullScreenRule.triggered(by: rules, summaries: small) == .none)
        #expect(PetFullScreenRule.triggered(by: rules, summaries: [:]) == .none)
    }

    @Test func theFirstMatchingRuleWinsEachState() {
        let rules = [
            PetFullScreenRule(bundleIdentifiers: ["com.example.first"], physics: .float),
            PetFullScreenRule(bundleIdentifiers: ["com.example.second"], physics: .ground, visibility: .hidden)
        ]
        let both = [
            "com.example.first": AppWindowSummary(coversDisplay: true, topLevel: 0),
            "com.example.second": AppWindowSummary(coversDisplay: true, topLevel: 0)
        ]
        #expect(PetFullScreenRule.triggered(by: rules, summaries: both) == PetStateSettings(physics: .float, visibility: .hidden))
    }

    @Test func aCommandBeatsATriggerWhichBeatsTheDefaultAndRevertingFallsBack() {
        let trigger = PetStateSettings(physics: .float, input: .off, level: .above(bundleIdentifier: "com.example.saver"))
        let commands = PetStateSettings(physics: .ground, visibility: .hidden)
        let states = PetEffectiveStates.resolve(commands: commands, trigger: trigger)
        #expect(states.physics == .ground && states.source(of: .physics) == .command)
        #expect(states.input == .off && states.source(of: .input) == .trigger)
        #expect(states.visibility == .hidden && states.source(of: .visibility) == .command)
        #expect(states.level == .above(bundleIdentifier: "com.example.saver") && states.source(of: .level) == .trigger)
        let reverted = PetEffectiveStates.resolve(commands: commands, trigger: .none)
        #expect(reverted.input == .on && reverted.source(of: .input) == .defaultValue)
        #expect(reverted.level == .normal)
        #expect(PetEffectiveStates.resolve(commands: .none, trigger: .none) == .defaults)
    }

    @Test func levelTextRoundTrips() {
        #expect(PetLevel(text: "normal") == .normal)
        #expect(PetLevel(text: "above com.example.saver") == .above(bundleIdentifier: "com.example.saver"))
        #expect(PetLevel(text: "above") == nil)
        #expect(PetLevel(text: "above a b") == nil)
        #expect(PetLevel(text: "sideways") == nil)
        #expect(PetLevel.above(bundleIdentifier: "com.example.saver").text == "above com.example.saver")
    }
}

@Suite("app windows")
struct AppWindowTests {
    private static let saverProcess: Int32 = 1733
    private static let otherProcess: Int32 = 42
    private static let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private static let secondDisplay = CGRect(x: 1728, y: -200, width: 2560, height: 1440)

    private func window(
        owner: Int32 = AppWindowTests.saverProcess,
        bounds: CGRect = AppWindowTests.display,
        level: Int = 1000,
        alpha: Double = 1,
        isOnScreen: Bool = true
    ) -> AppWindow {
        AppWindow(ownerProcessIdentifier: owner, bounds: bounds, level: level, alpha: alpha, isOnScreen: isOnScreen)
    }

    private func summary(_ windows: [AppWindow]) -> AppWindowSummary? {
        WindowDetection.summaries(
            windows: windows,
            processIdentifiersByBundleIdentifier: ["com.example.saver": [AppWindowTests.saverProcess]],
            displayBounds: [AppWindowTests.display, AppWindowTests.secondDisplay]
        )["com.example.saver"]
    }

    @Test func aFullScreenWindowCoversADisplayAndTheTopLevelIsTheHighestShownWindow() {
        #expect(summary([window()]) == AppWindowSummary(coversDisplay: true, topLevel: 1000))
        #expect(summary([window(bounds: AppWindowTests.secondDisplay, level: 1001)]) == AppWindowSummary(coversDisplay: true, topLevel: 1001))
        #expect(summary([window(bounds: CGRect(x: 0, y: 0, width: 400, height: 300), level: 3), window(level: 25)])?.topLevel == 25)
    }

    @Test func smallHiddenTransparentOrForeignWindowsDoNotCover() {
        #expect(summary([]) == nil)
        #expect(summary([window(bounds: CGRect(x: 0, y: 0, width: 400, height: 300))]) == AppWindowSummary(coversDisplay: false, topLevel: 1000))
        #expect(summary([window(bounds: CGRect(x: 0, y: 0, width: 1728, height: 900))])?.coversDisplay == false)
        #expect(summary([window(alpha: 0)]) == nil)
        #expect(summary([window(isOnScreen: false)]) == nil)
        #expect(summary([window(owner: AppWindowTests.otherProcess)]) == nil)
    }

    @Test func levelAboveAnAppIsOneAboveItsTopWindowAndNeverAtTheShieldingLevel() {
        let shielding = 2_147_483_628
        let summaries = ["com.example.saver": AppWindowSummary(coversDisplay: true, topLevel: 1000)]
        func level(_ petLevel: PetLevel, _ known: [String: AppWindowSummary]) -> Int {
            WindowDetection.windowLevel(for: petLevel, summaries: known, petLevel: 1000, shieldingLevel: shielding)
        }
        #expect(level(.normal, summaries) == 1000)
        #expect(level(.above(bundleIdentifier: "com.example.saver"), summaries) == 1001)
        #expect(level(.above(bundleIdentifier: "com.example.gone"), summaries) == 1000)
        #expect(level(.above(bundleIdentifier: "com.example.saver"), ["com.example.saver": AppWindowSummary(coversDisplay: false, topLevel: 3)]) == 1000)
        #expect(level(.above(bundleIdentifier: "com.example.saver"), ["com.example.saver": AppWindowSummary(coversDisplay: true, topLevel: shielding)]) == shielding - 1)
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

    private func run(_ motion: inout SpaceMotion, seconds: Double, each: (SpaceMotion) -> Void = { _ in }) {
        var elapsed = 0.0
        while elapsed < seconds {
            motion.advance(elapsedSeconds: SpaceMotionTests.tick, area: SpaceMotionTests.area)
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

    @Test func whenTheScreensaverGoesThePetFallsPlayingFallAndLandsUpright() {
        var motion = SpaceMotion(launchingFrom: SpaceMotionTests.launch, seed: SpaceMotion.seed(forPetKey: "pet-fall"))
        run(&motion, seconds: 8)
        motion.returnToGround()
        #expect(motion.phase == .falling)
        #expect(motion.animationName == .fall)
        #expect(!motion.isOnGround)
        var lastHeight = motion.center.y
        var fallSeconds = 0.0
        while motion.phase == .falling {
            #expect(motion.animationName == .fall)
            run(&motion, seconds: SpaceMotionTests.tick)
            #expect(motion.center.y <= lastHeight + 2)
            lastHeight = motion.center.y
            fallSeconds += SpaceMotionTests.tick
            #expect(fallSeconds < 3)
        }
        #expect(motion.phase == .landed)
        #expect(motion.isOnGround)
        #expect(motion.center.y == SpaceMotionTests.area.groundCenterY)
        #expect(motion.rotationInRadians == 0)
        #expect(motion.animationName == .idle)
        let landedAt = motion.center
        run(&motion, seconds: 1)
        #expect(motion.center == landedAt)
    }

    @Test func returningToGroundIsIdempotentAndLandingIsFinal() {
        var motion = SpaceMotion(launchingFrom: SpaceMotionTests.launch, seed: 7)
        motion.returnToGround()
        motion.returnToGround()
        #expect(motion.phase == .falling)
        run(&motion, seconds: 60)
        #expect(motion.phase == .landed)
        motion.returnToGround()
        #expect(motion.phase == .landed)
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

@Suite("input off makes pets inert")
struct InertPetTests {
    @Test func inputOffOrAPetStillComingBackFromSpaceTakesNoInput() {
        #expect(PetInputPolicy.acceptsInput(input: .on, isReturningFromSpace: false))
        #expect(!PetInputPolicy.acceptsInput(input: .on, isReturningFromSpace: true))
        #expect(!PetInputPolicy.acceptsInput(input: .off, isReturningFromSpace: false))
        #expect(!PetInputPolicy.acceptsInput(input: .off, isReturningFromSpace: true))
    }

    @Test func aFocusCommandInFlightIsDroppedWithoutAReport() throws {
        let registry = RunningFocusCommands()
        let reports = ReportRecorder()
        let focuser = CommandFocuser(
            arguments: ["/bin/sleep", "5"],
            waitsForCompletion: false,
            report: { line in reports.append(line) },
            runningCommands: registry
        )
        focuser.focus(FocusRequest(sessionId: "inert", processIdentifier: nil, focusTarget: nil, group: "inert", agent: .claudeCode, tmuxTarget: nil, allowsClientSwitch: true))
        #expect(registry.runningCount == 1)
        #expect(registry.cancelAll() == 1)
        let deadline = Date().addingTimeInterval(2)
        while registry.runningCount > 0 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        #expect(registry.runningCount == 0)
        #expect(reports.lines.isEmpty)
    }
}

final class ReportRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    func append(_ line: String) {
        lock.lock()
        recorded.append(line)
        lock.unlock()
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}
