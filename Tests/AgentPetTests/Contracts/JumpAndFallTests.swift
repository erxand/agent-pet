import Foundation
import Testing
@testable import AgentPetCore

@Suite("jump and fall: optional animations with stand-ins")
struct JumpAndFallTests {
    private let sprites = Sandbox.packageRoot.appendingPathComponent("sprites", isDirectory: true)

    @Test func everyShippedPackLoadsTwoJumpAndTwoFallFrames() {
        let loader = SpritePackLoader(packsDirectory: sprites, extraDirectoryPaths: [])
        for name in loader.availablePackNames() {
            guard case .loaded(let pack) = loader.load(packNamed: name) else {
                Issue.record("\(name) did not load")
                continue
            }
            #expect(pack.sheet.jump.count == 2, "\(name)")
            #expect(pack.sheet.fall.count == 2, "\(name)")
            #expect(SpriteAnimationName.jump.shown(in: pack.sheet) == .jump, "\(name)")
            #expect(SpriteAnimationName.fall.shown(in: pack.sheet) == .fall, "\(name)")
        }
    }

    @Test func aPackWithoutThemLoadsAndShowsWalkForJumpAndIdleForFall() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        let golem = sandbox.spritesDirectory.appendingPathComponent("golem", isDirectory: true)
        for animationName in [SpriteAnimationName.jump, .fall] {
            try FileManager.default.removeItem(at: golem.appendingPathComponent(animationName.packFileName))
        }
        let loader = SpritePackLoader(packsDirectory: sandbox.spritesDirectory, extraDirectoryPaths: [])
        guard case .loaded(let pack) = loader.load(packNamed: "golem") else {
            Issue.record("golem without jump.txt and fall.txt did not load")
            return
        }
        #expect(pack.sheet.jump.isEmpty && pack.sheet.fall.isEmpty)
        #expect(SpriteAnimationName.jump.shown(in: pack.sheet) == .walk)
        #expect(SpriteAnimationName.fall.shown(in: pack.sheet) == .idle)
        #expect(SpriteAnimationName.jump.shown(in: SpriteSheet.claude8Bit) == .walk)
        #expect(SpriteAnimationName.fall.shown(in: SpriteSheet.claude8Bit) == .idle)
    }

    @Test func onlyJumpAndFallHaveStandIns() {
        for animationName in SpriteAnimationName.allCases {
            switch animationName {
            case .jump: #expect(animationName.standIn == .walk)
            case .fall: #expect(animationName.standIn == .idle)
            default: #expect(animationName.standIn == nil)
            }
        }
    }

    @Test func renderDrawsEachJumpAndFallFrame() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        let idle = try sandbox.run(["render", "--pack", "golem"])
        var drawn: Set<String> = [idle.standardOutput]
        for animationName in ["jump", "fall"] {
            for frame in ["0", "1"] {
                let run = try sandbox.run(["render", "--pack", "golem", "--animation", animationName, "--frame", frame])
                #expect(run.exitStatus == 0, "\(animationName) \(frame)")
                #expect(run.standardOutput.contains("\u{2580}"))
                drawn.insert(run.standardOutput)
            }
            let beyond = try sandbox.run(["render", "--pack", "golem", "--animation", animationName, "--frame", "2"])
            #expect(beyond.exitStatus == 2)
        }
        #expect(drawn.count == 5)
    }

    @Test func aFallingFloatPlaysFall() {
        var motion = SpaceMotion(launchingFrom: CGPoint(x: 400, y: 50), seed: 11)
        #expect(motion.animationName == .idle)
        motion.returnToGround()
        #expect(motion.animationName == .fall)
    }
}
