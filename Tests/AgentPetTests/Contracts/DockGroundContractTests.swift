import CoreGraphics
import Foundation
import Testing
@testable import AgentPetCore

private final class FakeDockAccess: DockAccessChecking {
    var granted: Bool
    private(set) var asks = 0
    private(set) var checks = 0

    init(granted: Bool) {
        self.granted = granted
    }

    func isGranted() -> Bool {
        checks += 1
        return granted
    }

    var onAsk: () -> Void = {}

    func ask() -> Bool {
        asks += 1
        onAsk()
        return granted
    }
}

private final class ClockBox {
    var now: TimeInterval = 0
    var ensured = 0
}

@Suite("the Dock as ground: config, capability, access and pack format")
struct DockGroundContractTests {
    @Test func theConfigKeyDefaultsOn() {
        #expect(AgentPetConfiguration.defaults.standsOnDock)
        #expect(ConfigurationFile.parse(Data("{}".utf8)).standsOnDock)
        #expect(!ConfigurationFile.parse(Data(#"{"dockGround": false}"#.utf8)).standsOnDock)
        #expect(ConfigurationFile.parse(Data(#"{"dockGround": "no"}"#.utf8)).standsOnDock)
    }

    @Test func theCapabilityIsListed() {
        #expect(AgentPetCapability.allCases.map { capability in capability.rawValue }.contains("dock-ground"))
    }

    private func temporaryFiles() throws -> (DockAccessFiles, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dock-access-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = DockAccessFiles(
            reportFile: folder.appendingPathComponent("dock-access.json"),
            requestFile: folder.appendingPathComponent("control/dock-access-ask")
        )
        return (files, folder)
    }

    @Test func theDaemonReportsItsOwnAccessAndOnlyAsksWhenRequested() throws {
        let (files, folder) = try temporaryFiles()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ClockBox()
        clock.now = 100
        let access = FakeDockAccess(granted: false)
        let reporter = DockAccessReporter(files: files, access: access, processIdentifier: 4242, clock: { clock.now })
        reporter.tick()
        #expect(files.loadReport() == DockAccessReport(granted: false, processIdentifier: 4242, checkedAt: 100, askedAt: nil))
        clock.now = 101
        reporter.tick()
        #expect(access.checks == 1)
        #expect(access.asks == 0)

        access.granted = true
        clock.now = 106
        reporter.tick()
        #expect(reporter.isGranted)
        #expect(files.loadReport()?.granted == true)
        #expect(access.asks == 0)

        files.writeRequest(nonce: "first")
        access.onAsk = { clock.now += 2 }
        clock.now = 107
        reporter.tick()
        #expect(access.asks == 1)
        #expect(files.loadReport()?.askNonce == "first")
        #expect(files.loadReport()?.askedAt == 109)
        #expect(!FileManager.default.fileExists(atPath: files.requestFile.path))
    }

    @Test func aSecondRequestSoonAfterIsAnsweredWithoutASecondPrompt() throws {
        let (files, folder) = try temporaryFiles()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ClockBox()
        let access = FakeDockAccess(granted: false)
        let reporter = DockAccessReporter(files: files, access: access, processIdentifier: 4242, clock: { clock.now })
        files.writeRequest(nonce: "first")
        reporter.tick()
        clock.now = 3
        files.writeRequest(nonce: "second")
        reporter.tick()
        #expect(access.asks == 1)
        #expect(files.loadReport()?.askNonce == "second")
        clock.now = 20
        files.writeRequest(nonce: "third")
        reporter.tick()
        #expect(access.asks == 2)
    }

    @Test func theReportIsRewrittenWhenItIsMissingOrNamesAnotherDaemon() throws {
        let (files, folder) = try temporaryFiles()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ClockBox()
        let reporter = DockAccessReporter(files: files, access: FakeDockAccess(granted: true), processIdentifier: 4242, clock: { clock.now })
        reporter.tick()
        try FileManager.default.removeItem(at: files.reportFile)
        clock.now = 2
        reporter.tick()
        #expect(files.loadReport() == nil)
        clock.now = 6
        reporter.tick()
        #expect(files.loadReport()?.processIdentifier == 4242)
        files.save(DockAccessReport(granted: false, processIdentifier: 77, checkedAt: 6, askedAt: nil))
        clock.now = 12
        reporter.tick()
        #expect(files.loadReport() == DockAccessReport(granted: true, processIdentifier: 4242, checkedAt: 12, askedAt: nil))
    }

    private func environment(
        files: DockAccessFiles,
        daemon: Int32?,
        clock: ClockBox,
        start: DaemonStart = .launchAgent,
        nonce: String = "nonce",
        onSleep: @escaping () -> Void = {}
    ) -> DockAccessCommand.Environment {
        DockAccessCommand.Environment(
            files: files,
            liveDaemonProcessIdentifier: { daemon },
            startDaemon: {
                clock.ensured += 1
                return start
            },
            makeNonce: { nonce },
            now: { clock.now },
            sleep: { seconds in
                clock.now += seconds
                onSleep()
            }
        )
    }

    @Test func theCommandAnswersWithTheDaemonsReportNotItsOwnProcess() throws {
        let (files, folder) = try temporaryFiles()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ClockBox()
        #expect(DockAccessCommand.run(flags: ParsedFlags(arguments: []), environment: environment(files: files, daemon: 4242, clock: clock)) == ExitCode.failure)

        files.save(DockAccessReport(granted: true, processIdentifier: 99, checkedAt: 1, askedAt: nil))
        #expect(DockAccessCommand.run(flags: ParsedFlags(arguments: []), environment: environment(files: files, daemon: 4242, clock: clock)) == ExitCode.failure)
        #expect(DockAccessCommand.run(flags: ParsedFlags(arguments: []), environment: environment(files: files, daemon: nil, clock: clock)) == ExitCode.failure)

        files.save(DockAccessReport(granted: true, processIdentifier: 4242, checkedAt: 1, askedAt: nil))
        #expect(DockAccessCommand.run(flags: ParsedFlags(arguments: []), environment: environment(files: files, daemon: 4242, clock: clock)) == ExitCode.success)
        #expect(!FileManager.default.fileExists(atPath: files.requestFile.path))
        #expect(clock.ensured == 0)
    }

    @Test func askIsHandedToTheDaemonAndMatchedByItsNonce() throws {
        let (files, folder) = try temporaryFiles()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ClockBox()
        clock.now = 500
        let access = FakeDockAccess(granted: true)
        let reporter = DockAccessReporter(files: files, access: access, processIdentifier: 4242, clock: { clock.now })
        let asking = environment(files: files, daemon: 4242, clock: clock, nonce: "one") { reporter.tick() }
        #expect(DockAccessCommand.run(flags: ParsedFlags(arguments: ["--ask"]), environment: asking) == ExitCode.success)
        #expect(clock.ensured == 1)
        #expect(access.asks == 1)

        let unanswered = environment(files: files, daemon: 4242, clock: clock, nonce: "two")
        #expect(DockAccessCommand.run(flags: ParsedFlags(arguments: ["--ask"]), environment: unanswered) == ExitCode.failure)
        #expect(files.pendingRequestNonce() == "two")

        let joining = environment(files: files, daemon: 4242, clock: clock, nonce: "three") { reporter.tick() }
        #expect(DockAccessCommand.run(flags: ParsedFlags(arguments: ["--ask"]), environment: joining) == ExitCode.success)
        #expect(files.loadReport()?.askNonce == "two")
        #expect(access.asks == 1)
    }

    @Test func onlyADaemonLaunchdDidNotStartIsNamedAsAnotherAppsGrant() throws {
        let (files, folder) = try temporaryFiles()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ClockBox()
        let access = FakeDockAccess(granted: false)
        let reporter = DockAccessReporter(files: files, access: access, processIdentifier: 4242, clock: { clock.now })
        let warned: Set<DaemonStart> = [.spawnedByThisCommand, .alreadyRunningWithoutLaunchAgent]
        for start in [DaemonStart.spawnedByThisCommand, .alreadyRunningWithoutLaunchAgent, .spawnedOnItsOwn, .launchAgent] {
            clock.now += 60
            var errors: [String] = []
            var asking = environment(files: files, daemon: 4242, clock: clock, start: start, nonce: "\(start)") { reporter.tick() }
            asking.writeError = { line in errors.append(line) }
            #expect(DockAccessCommand.run(flags: ParsedFlags(arguments: ["--ask"]), environment: asking) == ExitCode.failure)
            let namesTheLauncher = errors.contains { line in line.contains("the app that started it") }
            #expect(namesTheLauncher == warned.contains(start), "\(start)")
            #expect(errors.contains { line in line.contains(DockAccessCommand.settingsHint) })
        }
        #expect(access.asks == 4)
    }

    @Test func theDaemonClaimsARequestSoALaterOneSurvives() throws {
        let (files, folder) = try temporaryFiles()
        defer { try? FileManager.default.removeItem(at: folder) }
        files.writeRequest(nonce: "first")
        #expect(files.consumeRequest() == "first")
        #expect(files.consumeRequest() == nil)
        files.writeRequest(nonce: "second")
        #expect(files.pendingRequestNonce() == "second")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: files.requestFile.deletingLastPathComponent().path)
        #expect(leftovers == [files.requestFile.lastPathComponent])
    }

    @Test func theDaemonClearsEveryClaimLeftByAnEarlierRunAtStart() throws {
        let (files, folder) = try temporaryFiles()
        defer { try? FileManager.default.removeItem(at: folder) }
        let directory = files.requestFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stale = directory.appendingPathComponent(".dock-access-ask.claimed-old")
        let fresh = directory.appendingPathComponent(".dock-access-ask.claimed-new")
        try Data("old".utf8).write(to: stale)
        try Data("new".utf8).write(to: fresh)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: stale.path)
        let reporter = DockAccessReporter(files: files, access: FakeDockAccess(granted: false), processIdentifier: 4242)
        reporter.tick()
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(!FileManager.default.fileExists(atPath: fresh.path))
    }

    private final class StarterLog {
        var started = 0
        var spawned = 0
    }

    private func starter(
        running: Int32?,
        parent: Int32?,
        agent: Bool,
        disclaims: Bool,
        log: StarterLog
    ) -> DaemonCommand.Starter {
        DaemonCommand.Starter(
            launchAgentIsInstalled: { agent },
            startLaunchAgent: { log.started += 1 },
            runningDaemon: { running },
            parentOf: { _ in parent },
            spawnDetached: {
                log.spawned += 1
                return disclaims
            }
        )
    }

    @Test func theDaemonIsStartedByLaunchdWhenItCanBeAndOtherwiseOnItsOwn() {
        let cases: [(Int32?, Int32?, Bool, Bool, DaemonStart, Int, Int)] = [
            (7, 1, true, true, .launchAgent, 1, 0),
            (7, 55, true, true, .alreadyRunningWithoutLaunchAgent, 0, 0),
            (7, 1, false, true, .alreadyRunningWithoutLaunchAgent, 0, 0),
            (nil, nil, true, true, .launchAgent, 1, 0),
            (nil, nil, false, true, .spawnedOnItsOwn, 0, 1),
            (nil, nil, false, false, .spawnedByThisCommand, 0, 1)
        ]
        for (running, parent, agent, disclaims, expected, starts, spawns) in cases {
            let log = StarterLog()
            let start = DaemonCommand.ensureRunningOnItsOwn(
                using: starter(running: running, parent: parent, agent: agent, disclaims: disclaims, log: log)
            )
            #expect(start == expected)
            #expect(log.started == starts)
            #expect(log.spawned == spawns)
        }
        #expect(ProcessParent.of(getpid()) == getppid())
    }

    @Test func aSpawnedDaemonInheritsNoDescriptorButItsStandardStreams() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("spawn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var descriptors: [Int32] = [0, 0]
        #expect(pipe(&descriptors) == 0)
        defer {
            close(descriptors[0])
            close(descriptors[1])
        }
        let logPath = folder.appendingPathComponent("log").path
        let spawned = try #require(ResponsibilityDisclaimingSpawn.spawn(
            executablePath: "/bin/sh",
            arguments: ["-c", "for descriptor in 0 1 2 \(descriptors[0]) \(descriptors[1]); do [ -e /dev/fd/$descriptor ] && echo open $descriptor; done"],
            logPath: logPath
        ))
        var status: Int32 = 0
        waitpid(spawned.processIdentifier, &status, 0)
        let lines = try String(contentsOfFile: logPath, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines.contains("open 0") && lines.contains("open 1") && lines.contains("open 2"))
        #expect(!lines.contains("open \(descriptors[0])"))
        #expect(!lines.contains("open \(descriptors[1])"))
    }

    @Test func jumpAndFallAreOptionalAndStandInForWalkAndIdle() {
        #expect(SpriteAnimationName.jump.isOptionalInPack)
        #expect(SpriteAnimationName.fall.isOptionalInPack)
        #expect(SpriteAnimationName.jump.standIn == .walk)
        #expect(SpriteAnimationName.fall.standIn == .idle)
        let sheet = SpriteSheet.claude8Bit
        #expect(SpriteAnimationName.jump.shown(in: sheet) == .walk)
        #expect(SpriteAnimationName.fall.shown(in: sheet) == .idle)
        #expect(SpriteAnimationName.emerge.shown(in: sheet) == .emerge)
    }

    @Test func aPackWithJumpAndFallFramesShowsThem() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dock-ground-pack-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.copyItem(at: Sandbox.packageRoot.appendingPathComponent("sprites/claude", isDirectory: true), to: folder)
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("jump.txt"))
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("fall.txt"))
        let walkText = try String(contentsOf: folder.appendingPathComponent("walk.txt"), encoding: .utf8)
        let idleText = try String(contentsOf: folder.appendingPathComponent("idle.txt"), encoding: .utf8)

        guard case .loaded(let without) = SpritePackLoader().load(packDirectory: folder) else {
            Issue.record("the pack without jump and fall frames did not load")
            return
        }
        #expect(without.sheet.jump.isEmpty && without.sheet.fall.isEmpty)
        #expect(SpriteAnimationName.fall.shown(in: without.sheet) == .idle)

        try walkText.write(to: folder.appendingPathComponent("jump.txt"), atomically: true, encoding: .utf8)
        try idleText.write(to: folder.appendingPathComponent("fall.txt"), atomically: true, encoding: .utf8)
        guard case .loaded(let with) = SpritePackLoader().load(packDirectory: folder) else {
            Issue.record("the pack with jump and fall frames did not load")
            return
        }
        #expect(with.sheet.jump.count == without.sheet.walk.count)
        #expect(with.sheet.fall.count == without.sheet.idle.count)
        #expect(SpriteAnimationName.jump.shown(in: with.sheet) == .jump)
        #expect(SpriteAnimationName.fall.shown(in: with.sheet) == .fall)
    }

    @Test func aFloatingPetThatFallsPlaysFall() {
        var motion = SpaceMotion(launchingFrom: CGPoint(x: 400, y: 300), seed: 7)
        #expect(motion.animationName == .idle)
        motion.returnToGround()
        #expect(motion.animationName == .fall)
    }
}
