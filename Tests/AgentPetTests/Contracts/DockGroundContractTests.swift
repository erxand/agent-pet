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

    func ask() -> Bool {
        asks += 1
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
        let access = FakeDockAccess(granted: false)
        let reporter = DockAccessReporter(files: files, access: access, processIdentifier: 4242)
        reporter.tick(now: 100)
        #expect(files.loadReport() == DockAccessReport(granted: false, processIdentifier: 4242, checkedAt: 100, askedAt: nil))
        reporter.tick(now: 101)
        #expect(access.checks == 1)
        #expect(access.asks == 0)

        access.granted = true
        reporter.tick(now: 106)
        #expect(reporter.isGranted)
        #expect(files.loadReport()?.granted == true)
        #expect(access.asks == 0)

        files.writeRequest()
        reporter.tick(now: 107)
        #expect(access.asks == 1)
        #expect(files.loadReport()?.askedAt == 107)
        #expect(!FileManager.default.fileExists(atPath: files.requestFile.path))
    }

    private func environment(files: DockAccessFiles, daemon: Int32?, clock: ClockBox, onSleep: @escaping () -> Void = {}) -> DockAccessCommand.Environment {
        DockAccessCommand.Environment(
            files: files,
            liveDaemonProcessIdentifier: { daemon },
            ensureDaemon: { clock.ensured += 1 },
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

    @Test func askIsHandedToTheDaemonWhichCallsMacOSItself() throws {
        let (files, folder) = try temporaryFiles()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ClockBox()
        clock.now = 500
        let access = FakeDockAccess(granted: true)
        let reporter = DockAccessReporter(files: files, access: access, processIdentifier: 4242)
        let asking = environment(files: files, daemon: 4242, clock: clock) { reporter.tick(now: clock.now) }
        #expect(DockAccessCommand.run(flags: ParsedFlags(arguments: ["--ask"]), environment: asking) == ExitCode.success)
        #expect(clock.ensured == 1)
        #expect(access.asks == 1)

        let silent = environment(files: files, daemon: 4242, clock: clock)
        #expect(DockAccessCommand.run(flags: ParsedFlags(arguments: ["--ask"]), environment: silent) == ExitCode.failure)
        #expect(access.asks == 1)
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
