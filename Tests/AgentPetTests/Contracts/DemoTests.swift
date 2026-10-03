import Foundation
import Testing
@testable import AgentPetCore

final class RecordingDemoStage: DemoStage {
    private(set) var presentedPets: [[PetDisplayItem]] = []
    private(set) var titles: [DemoTitleCard?] = []
    private(set) var captions: [DemoCaption?] = []
    private(set) var toasts: [DemoToast] = []
    private(set) var tearDownCount = 0

    var isSettled: Bool { true }
    func present(scene: DemoScene, number: Int, of sceneCount: Int) {}
    func present(title: DemoTitleCard?) { titles.append(title) }
    func present(caption: DemoCaption?) { captions.append(caption) }
    func present(pets: [PetDisplayItem], labelPlacement: LabelPlacement) { presentedPets.append(pets) }
    func present(toast: DemoToast) { toasts.append(toast) }
    func advance(elapsedSeconds: Double, sceneProgress: Double) {}
    func tearDown() { tearDownCount += 1 }
}

@Suite("demo timeline")
struct DemoTimelineTests {
    private static let tickInSeconds = 0.05

    private func runner(for name: DemoSceneName, stage: RecordingDemoStage) throws -> DemoRunner {
        let scene = try #require(DemoScript.scene(named: name))
        return DemoRunner(scenes: [scene], stage: stage)
    }

    private func advance(_ runner: DemoRunner, by seconds: Double) {
        var remaining = seconds
        while remaining > 0 {
            let step = min(DemoTimelineTests.tickInSeconds, remaining)
            runner.advance(byElapsedSeconds: step)
            remaining -= step
        }
    }

    @Test func everySceneIsScriptedOnceInOrderAndTheTourRunsAboutAMinute() {
        #expect(DemoScript.scenes.map { scene in scene.name } == DemoSceneName.allCases)
        #expect(DemoScript.totalDurationInSeconds >= 55)
        #expect(DemoScript.totalDurationInSeconds <= 75)
    }

    @Test func stepsStayInsideTheirSceneInOrderAndNameRealActors() {
        let castIds = Set(DemoScript.cast.map { actor in actor.sessionId })
        #expect(castIds.count == DemoScript.cast.count)
        for scene in DemoScript.scenes {
            let offsets = scene.steps.map { step in step.offsetInSeconds }
            #expect(offsets == offsets.sorted())
            #expect(offsets.allSatisfy { offset in offset >= 0 && offset < scene.durationInSeconds })
            for step in scene.steps {
                switch step.action {
                case .show(let actorId, _, _), .click(let actorId):
                    #expect(castIds.contains(actorId))
                case .hide(let actorIds):
                    #expect(actorIds.allSatisfy { actorId in castIds.contains(actorId) })
                case .showTitle, .hideTitle, .toast:
                    break
                }
            }
        }
    }

    @Test func everyPetIsGoneBeforeItsSceneEnds() throws {
        for scene in DemoScript.scenes {
            let stage = RecordingDemoStage()
            let runner = DemoRunner(scenes: [scene], stage: stage)
            advance(runner, by: scene.durationInSeconds - 0.01)
            #expect(runner.currentScene?.name == scene.name)
            #expect(runner.displayedPets.isEmpty, "scene \(scene.name.rawValue) still shows pets at its end")
        }
    }

    @Test func petScenesShowWhatTheirCaptionPromises() throws {
        let climbStage = RecordingDemoStage()
        let climb = try runner(for: .climbOut, stage: climbStage)
        advance(climb, by: 2)
        #expect(climb.displayedPets.map { item in item.mood } == [.ready])

        let inputStage = RecordingDemoStage()
        let needsInput = try runner(for: .needsInput, stage: inputStage)
        advance(needsInput, by: 2)
        #expect(needsInput.displayedPets.map { item in item.mood } == [.needsInput])

        let laneStage = RecordingDemoStage()
        let lanes = try runner(for: .lanes, stage: laneStage)
        advance(lanes, by: 4)
        let lanePets = lanes.displayedPets
        #expect(lanePets.count == 5)
        #expect(Set(lanePets.compactMap { item in item.session.sprite }).count == 5)

        let reservedStage = RecordingDemoStage()
        let reserved = try runner(for: .reserved, stage: reservedStage)
        advance(reserved, by: 4)
        #expect(reserved.displayedPets.last?.session.sprite == SpritePackLoader.defaultPackName)
    }

    @Test func theGroupScenePutsThreeAgentsInOnePetAndNamesTheWaitingOne() throws {
        let stage = RecordingDemoStage()
        let group = try runner(for: .group, stage: stage)
        advance(group, by: 2)
        let first = try #require(group.displayedPets.first)
        #expect(group.displayedPets.count == 1)
        #expect(first.memberSessionIds.count == 3)
        #expect(first.label == "NIST-1025")
        #expect(first.bubbleCaption == "review")
        #expect(first.mood == .ready)

        advance(group, by: 3)
        let second = try #require(group.displayedPets.first)
        #expect(group.displayedPets.count == 1)
        #expect(second.bubbleCaption == "qa")
        #expect(second.mood == .needsInput)
    }

    @Test func clashingNamesGetTheirSessionSuffix() throws {
        let stage = RecordingDemoStage()
        let nametags = try runner(for: .nametags, stage: stage)
        advance(nametags, by: 3)
        #expect(nametags.displayedPets.map { item in item.label } == ["server 7f3a", "server c21e"])
    }

    @Test func aClickHidesThePetAndOnlyShowsAnAchievement() throws {
        let stage = RecordingDemoStage()
        let click = try runner(for: .click, stage: stage)
        advance(click, by: 2)
        let pet = try #require(click.displayedPets.first)
        click.handleClick(petKey: pet.petKey)
        #expect(click.displayedPets.isEmpty)
        #expect(stage.toasts == [DemoToast(title: "Achievement get!", body: "Back to deploy", sprite: "hatchling")])
        advance(click, by: 4)
        #expect(stage.toasts.count == 1)

        let unattendedStage = RecordingDemoStage()
        let unattended = try runner(for: .click, stage: unattendedStage)
        advance(unattended, by: 6)
        #expect(unattended.displayedPets.isEmpty)
        #expect(unattendedStage.toasts.map { toast in toast.body } == ["Back to deploy"])
    }

    @Test func aClickOnAGroupPetHidesEveryMember() throws {
        let stage = RecordingDemoStage()
        let group = try runner(for: .group, stage: stage)
        advance(group, by: 5)
        let pet = try #require(group.displayedPets.first)
        group.handleClick(petKey: pet.petKey)
        #expect(group.displayedPets.isEmpty)
        #expect(stage.toasts.first?.body == "Back to NIST-1025")
    }

    @Test func skippingMovesToTheNextSceneAndClearsThePets() {
        let stage = RecordingDemoStage()
        let runner = DemoRunner(scenes: DemoScript.scenes, stage: stage)
        runner.start()
        while runner.currentScene?.name != .lanes {
            runner.skipToNextScene()
        }
        advance(runner, by: 4)
        #expect(!runner.displayedPets.isEmpty)
        runner.skipToNextScene()
        #expect(runner.currentScene?.name == .group)
        #expect(runner.displayedPets.isEmpty)
        #expect(stage.presentedPets.last?.isEmpty == true)
        #expect(stage.captions.last??.text == DemoScript.scene(named: .group)?.caption)
    }

    @Test func theTourEndsWithNothingOnScreen() {
        let stage = RecordingDemoStage()
        let runner = DemoRunner(scenes: DemoScript.scenes, stage: stage)
        advance(runner, by: DemoScript.totalDurationInSeconds + 1)
        #expect(runner.isFinished)
        #expect(runner.displayedPets.isEmpty)
        #expect(stage.presentedPets.last?.isEmpty == true)
        #expect(stage.titles.last == .some(nil))
        #expect(stage.captions.last == .some(nil))
        #expect(stage.tearDownCount == 0)
        runner.stop()
        #expect(stage.tearDownCount == 1)
    }

    @Test func stopTearsDownOnceAndFreezesTheTimeline() throws {
        let stage = RecordingDemoStage()
        let lanes = try runner(for: .lanes, stage: stage)
        advance(lanes, by: 4)
        lanes.stop()
        lanes.stop()
        let presentedCount = stage.presentedPets.count
        advance(lanes, by: 4)
        lanes.skipToNextScene()
        #expect(stage.tearDownCount == 1)
        #expect(stage.presentedPets.count == presentedCount)
        #expect(lanes.isFinished)
    }

    @Test func theCastNeverLooksLikeARealSession() {
        let stage = RecordingDemoStage()
        let runner = DemoRunner(scenes: DemoScript.scenes, stage: stage)
        advance(runner, by: DemoScript.totalDurationInSeconds)
        let shownIds = stage.presentedPets.flatMap { items in items.flatMap { item in item.memberSessionIds } }
        #expect(!shownIds.isEmpty)
        #expect(shownIds.allSatisfy { sessionId in sessionId.hasPrefix("demo-") })
    }
}

@Suite("demo pixel font")
struct DemoPixelFontTests {
    @Test func everyGlyphIsNineRowsOfOneWidth() throws {
        for character in DemoPixelFont.characters {
            let rows = try #require(DemoPixelFont.glyphRows(for: character))
            #expect(rows.count == DemoPixelFont.glyphHeight)
            #expect(Set(rows.map { row in row.count }).count == 1, "glyph \(character) has ragged rows")
        }
    }

    @Test func everyWordTheDemoShowsCanBeDrawn() {
        var texts: [String] = [DemoScript.achievementTitle, DemoScript.clickToastBodyPrefix]
        for scene in DemoScript.scenes {
            if let caption = scene.caption { texts.append(caption) }
            for step in scene.steps {
                switch step.action {
                case .showTitle(let card):
                    texts.append(contentsOf: [card.title, card.subtitle] + (card.splash.map { splash in [splash] } ?? []))
                case .toast(let toast):
                    texts.append(contentsOf: [toast.title, toast.body])
                case .show, .hide, .click, .hideTitle:
                    break
                }
            }
        }
        texts.append(contentsOf: DemoScript.cast.map { actor in actor.nickname })
        for text in texts {
            #expect(DemoPixelFont.canRender(text), "cannot draw \(text)")
        }
    }

    @Test func lookAlikeLettersDiffer() {
        for (left, right) in [("N", "M"), ("V", "Y"), ("O", "0"), ("I", "l"), ("S", "5"), ("B", "8")] {
            #expect(DemoPixelFont.rows(for: left) != DemoPixelFont.rows(for: right), "\(left) and \(right) look the same")
        }
        #expect(DemoPixelFont.width(of: "il") == 1 + DemoPixelFont.glyphSpacing + 2)
    }

    @Test func theShippedSpritesAreFoundFromABuiltBinary() {
        let builtBinary = Sandbox.packageRoot.appendingPathComponent(".build/release/agent-pet").path
        let found = DemoSpriteDirectories.shippedSpritesDirectory(executablePath: builtBinary)
        #expect(found?.standardizedFileURL == Sandbox.packageRoot.appendingPathComponent("sprites", isDirectory: true).standardizedFileURL)
        #expect(DemoSpriteDirectories.shippedSpritesDirectory(executablePath: "/usr/bin/true") == nil)
        #expect(DemoSpriteDirectories.shippedSpritesDirectory(executablePath: nil) == nil)
    }
}

@Suite("demo command")
struct DemoCommandTests {
    @Test func listNamesEveryScene() throws {
        let sandbox = try Sandbox()
        let run = try sandbox.run(["demo", "--list"])
        #expect(run.exitStatus == 0)
        let lines = run.standardOutput.split(separator: "\n")
        #expect(lines.count == DemoSceneName.allCases.count + 1)
        for (line, name) in zip(lines, DemoSceneName.allCases) {
            #expect(line.hasPrefix(name.rawValue))
        }
        #expect(lines.last?.hasPrefix("total") == true)

        let one = try sandbox.run(["demo", "--scene", "group", "--list"])
        #expect(one.standardOutput.split(separator: "\n").first?.hasPrefix("group") == true)
    }

    @Test func badFlagsAreUsageErrors() throws {
        let sandbox = try Sandbox()
        let unknownScene = try sandbox.run(["demo", "--scene", "nosuch"])
        #expect(unknownScene.exitStatus == 2)
        #expect(unknownScene.standardError.contains("unknown scene nosuch"))
        #expect(unknownScene.standardError.contains("climb-out"))
        #expect(try sandbox.run(["demo", "--speed", "0", "--dry-run"]).exitStatus == 2)
        #expect(try sandbox.run(["demo", "--speed", "fast", "--dry-run"]).exitStatus == 2)
    }

    @Test func aDryRunTouchesNoSessionAndNoDaemon() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord([
            "sessionId": "real-session",
            "enabled": true,
            "visible": true,
            "mood": "ready",
            "updatedAt": 1_790_000_000.0
        ])
        let recordBefore = try Data(contentsOf: sandbox.recordURL("real-session"))
        let listingBefore = try FileManager.default.contentsOfDirectory(atPath: sandbox.stateDirectory.path).sorted()

        let run = try sandbox.run(["demo", "--dry-run", "--speed", "1000"])

        #expect(run.exitStatus == 0)
        #expect(run.standardOutput.contains("scene 10/10 finale"))
        #expect(run.standardOutput.contains("pets: NIST-1025 (golem needsInput bubble qa 3 members)"))
        #expect(run.standardOutput.contains("teardown"))
        #expect(try Data(contentsOf: sandbox.recordURL("real-session")) == recordBefore)
        #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.stateDirectory.path).sorted() == listingBefore)
        #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.sessionsDirectory.path) == ["real-session.json"])
        #expect(sandbox.tmuxCalls().isEmpty)
        #expect(!sandbox.exists(sandbox.hookLog))
        #expect(!sandbox.exists(sandbox.daemonLog))
    }

    @Test func aDryRunInAFreshHomeCreatesNothing() throws {
        let sandbox = try Sandbox()
        let freshHome = sandbox.home.deletingLastPathComponent().appendingPathComponent("fresh-home", isDirectory: true)
        try FileManager.default.createDirectory(at: freshHome, withIntermediateDirectories: true)
        let run = try sandbox.run(
            ["demo", "--dry-run", "--speed", "1000", "--scene", "click"],
            environment: ["HOME": freshHome.path, "CFFIXED_USER_HOME": freshHome.path]
        )
        #expect(run.exitStatus == 0)
        #expect(run.standardOutput.contains("toast: Achievement get! Back to deploy"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: freshHome.path).isEmpty)
    }

    @Test(arguments: [(SIGTERM, "SIGTERM"), (SIGINT, "ctrl-c")])
    func aSignalStopsTheDemoAndClosesEverything(signalNumber: Int32, signalName: String) throws {
        let sandbox = try Sandbox()
        let process = Process()
        process.executableURL = try Sandbox.binaryURL()
        process.arguments = ["demo", "--dry-run"]
        process.environment = ["HOME": sandbox.home.path, "CFFIXED_USER_HOME": sandbox.home.path, "PATH": "/usr/bin:/bin"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        Thread.sleep(forTimeInterval: 0.8)
        kill(process.processIdentifier, signalNumber)
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning { process.terminate() }
        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        #expect(process.terminationReason == .exit)
        #expect(process.terminationStatus == 128 + signalNumber)
        #expect(output.contains("teardown: every demo window closed"))
        #expect(output.contains("demo stopped by \(signalName)"))
        #expect(!output.contains("scene 2/10"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.sessionsDirectory.path).isEmpty)
    }
}
