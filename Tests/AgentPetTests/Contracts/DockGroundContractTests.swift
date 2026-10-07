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

    @Test func checkingAccessNeverAsks() {
        let access = FakeDockAccess(granted: false)
        #expect(DockAccessCommand.run(flags: ParsedFlags(arguments: []), access: access) == ExitCode.failure)
        #expect(access.asks == 0)
        #expect(access.checks == 1)
        access.granted = true
        #expect(DockAccessCommand.run(flags: ParsedFlags(arguments: []), access: access) == ExitCode.success)
        #expect(access.asks == 0)
    }

    @Test func onlyAskAsksMacOS() {
        let access = FakeDockAccess(granted: true)
        #expect(DockAccessCommand.run(flags: ParsedFlags(arguments: ["--ask"]), access: access) == ExitCode.success)
        #expect(access.asks == 1)
        #expect(access.checks == 0)
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
