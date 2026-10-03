import AppKit
import Foundation
import Testing
@testable import AgentPetCore

final class RecordingDemoStage: DemoStage {
    private(set) var presentedPets: [[PetDisplayItem]] = []
    private(set) var titles: [DemoTitleCard?] = []
    private(set) var captions: [DemoCaption?] = []
    private(set) var states: [[DemoStateMark]] = []
    private(set) var tearDownCount = 0

    var isSettled: Bool { true }
    func present(scene: DemoScene, number: Int, of sceneCount: Int) {}
    func present(title: DemoTitleCard?) { titles.append(title) }
    func present(caption: DemoCaption?) { captions.append(caption) }
    func present(states: [DemoStateMark]) { self.states.append(states) }
    func present(pets: [PetDisplayItem], labelPlacement: LabelPlacement) { presentedPets.append(pets) }
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

    @Test func everySceneIsScriptedOnceInOrderAndTheTourIsShort() {
        #expect(DemoScript.scenes.map { scene in scene.name } == DemoSceneName.allCases)
        #expect(DemoScript.scenes.map { scene in scene.name } == [.title, .states, .lanes, .click, .dive, .finale])
        #expect(DemoScript.totalDurationInSeconds >= 25)
        #expect(DemoScript.totalDurationInSeconds <= 35)
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
                case .showTitle, .hideTitle:
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
        let laneStage = RecordingDemoStage()
        let lanes = try runner(for: .lanes, stage: laneStage)
        advance(lanes, by: 2.5)
        let lanePets = lanes.displayedPets
        #expect(lanePets.count == 3)
        #expect(Set(lanePets.compactMap { item in item.session.sprite }).count == 3)

        let diveStage = RecordingDemoStage()
        let dive = try runner(for: .dive, stage: diveStage)
        advance(dive, by: 1.2)
        #expect(dive.displayedPets.map { item in item.label } == ["lint", "ui"])
        advance(dive, by: 1)
        #expect(dive.displayedPets.map { item in item.label } == ["ui"])
    }

    @Test func theStatesSceneShowsEveryRealMoodAndTheHiddenWorkingStateAtOnce() throws {
        let scene = try #require(DemoScript.scene(named: .states))
        let pets = scene.steps.compactMap { step -> (String, PetMood)? in
            if case .show(let actorId, let mood, _) = step.action { return (actorId, mood) }
            return nil
        }
        let lastShow = try #require(scene.steps.last { step in if case .show = step.action { return true } else { return false } })
        let hide = try #require(scene.steps.first { step in if case .hide = step.action { return true } else { return false } })
        #expect(hide.offsetInSeconds - lastShow.offsetInSeconds >= 7)
        #expect(scene.durationInSeconds >= 8 && scene.durationInSeconds <= 10)
        #expect(Set(pets.map { pet in pet.1 }) == Set(PetMood.allCases))
        #expect(pets.count == PetMood.allCases.count)
        #expect(scene.stateSlots.map { slot in slot.label } == ["Ready: turn done", "Needs your input", "Blocked", "Working: no pet"])
        #expect(scene.stateSlots.compactMap { slot in slot.actorId } == pets.map { pet in pet.0 })

        let stage = RecordingDemoStage()
        let states = try runner(for: .states, stage: stage)
        advance(states, by: 2)
        #expect(states.displayedPets.map { item in item.mood } == [.ready, .needsInput, .blocked])
        let marks = try #require(stage.states.last)
        #expect(marks.map { mark in mark.label } == scene.stateSlots.map { slot in slot.label })
        #expect(marks.last?.sessionId == nil)
        #expect(marks.last?.sprite == nil)
        #expect(marks.dropLast().allSatisfy { mark in mark.sessionId != nil && mark.sprite != nil })

        states.skipToNextScene()
        #expect(stage.states.last == [])
    }

    @Test func everySceneUsesThePillLabelsANewUserSees() {
        #expect(DemoScript.scenes.allSatisfy { scene in scene.labelPlacement == .pill })
    }

    @Test func aClickDivesThePetAndTheCaptionSaysWhatRealUseDoes() throws {
        let expected = "In real use, the terminal tab for deploy comes to the front."
        let stage = RecordingDemoStage()
        let click = try runner(for: .click, stage: stage)
        advance(click, by: 2)
        let pet = try #require(click.displayedPets.first)
        click.handleClick(petKey: pet.petKey)
        #expect(click.displayedPets.isEmpty)
        #expect(stage.captions.last == DemoCaption(text: expected, sceneNumber: 1, sceneCount: 1, accent: .cyan))
        let captionCount = stage.captions.count
        advance(click, by: 3)
        #expect(stage.captions.count == captionCount)

        let unattendedStage = RecordingDemoStage()
        let unattended = try runner(for: .click, stage: unattendedStage)
        advance(unattended, by: 4.5)
        #expect(unattended.displayedPets.isEmpty)
        #expect(unattendedStage.captions.last??.text == expected)
    }

    @Test func aSceneCaptionCarriesTheAccentOfItsPet() throws {
        let stage = RecordingDemoStage()
        let states = try runner(for: .states, stage: stage)
        states.start()
        #expect(stage.captions.last??.accent == .orange)
        let titleStage = RecordingDemoStage()
        let title = try runner(for: .title, stage: titleStage)
        title.start()
        #expect(titleStage.captions.last == .some(nil))
    }

    @Test func skippingMovesToTheNextSceneAndClearsThePets() {
        let stage = RecordingDemoStage()
        let runner = DemoRunner(scenes: DemoScript.scenes, stage: stage)
        runner.start()
        while runner.currentScene?.name != .lanes {
            runner.skipToNextScene()
        }
        advance(runner, by: 2.5)
        #expect(!runner.displayedPets.isEmpty)
        runner.skipToNextScene()
        #expect(runner.currentScene?.name == .click)
        #expect(runner.displayedPets.isEmpty)
        #expect(stage.presentedPets.last?.isEmpty == true)
        #expect(stage.captions.last??.text == DemoScript.scene(named: .click)?.caption)
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
        advance(lanes, by: 2.5)
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
        var texts: [String] = [DemoScript.clickCaption(petLabel: "deploy")]
        for scene in DemoScript.scenes {
            if let caption = scene.caption { texts.append(caption) }
            texts.append(contentsOf: scene.stateSlots.map { slot in slot.label })
            for step in scene.steps {
                switch step.action {
                case .showTitle(let card):
                    texts.append(contentsOf: [card.title, card.subtitle])
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

        let one = try sandbox.run(["demo", "--scene", "lanes", "--list"])
        #expect(one.standardOutput.split(separator: "\n").first?.hasPrefix("lanes") == true)

        for removed in ["group", "nametags", "reserved", "climb-out", "needs-input"] {
            #expect(try sandbox.run(["demo", "--scene", removed, "--list"]).exitStatus == 2)
        }
    }

    @Test func badFlagsAreUsageErrors() throws {
        let sandbox = try Sandbox()
        let unknownScene = try sandbox.run(["demo", "--scene", "nosuch"])
        #expect(unknownScene.exitStatus == 2)
        #expect(unknownScene.standardError.contains("unknown scene nosuch"))
        #expect(unknownScene.standardError.contains("states"))
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
        #expect(run.standardOutput.contains("scene 6/6 finale"))
        #expect(run.standardOutput.contains("states: Ready: turn done (claude), Needs your input (golem), Blocked (seon), Working: no pet (no pet)"))
        #expect(run.standardOutput.contains("pets: tests (hatchling ready), docs (mossling needsInput), api (nimbus ready)"))
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
        #expect(run.standardOutput.contains("caption: In real use, the terminal tab for deploy comes to the front."))
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
        #expect(output.contains("teardown: all demo windows are closed"))
        #expect(output.contains("demo stopped by \(signalName)"))
        #expect(!output.contains("scene 2/6"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.sessionsDirectory.path).isEmpty)
    }
}

@Suite("demo palette")
struct DemoPaletteTests {
    private static let minimumTextContrast = 4.5
    private static let minimumAccentContrast = 3.0

    @Test func everyTextColorReadsAtLeastFourAndAHalfToOneOnEveryPanelTone() {
        for text in DemoPalette.textColors {
            for background in DemoPalette.textBackgrounds {
                let ratio = DemoPalette.contrastRatio(text, background)
                #expect(ratio >= DemoPaletteTests.minimumTextContrast, "text \(text) on \(background) is \(ratio):1")
            }
        }
    }

    @Test func everyAccentStandsOutFromTheBarTrackAndThePanel() {
        for accent in AccentColor.allCases {
            for background in [DemoPalette.frame, DemoPalette.fill] {
                let ratio = DemoPalette.contrastRatio(DemoPalette.accentColor(accent), background)
                #expect(ratio >= DemoPaletteTests.minimumAccentContrast, "\(accent.rawValue) is \(ratio):1")
            }
        }
    }

    @Test func theContrastMathMatchesKnownValues() {
        let black = NSColor(hex: 0x000000)
        let white = NSColor(hex: 0xFFFFFF)
        #expect(abs(DemoPalette.contrastRatio(black, white) - 21) < 0.001)
        #expect(abs(DemoPalette.contrastRatio(white, white) - 1) < 0.001)
    }
}

@Suite("demo words")
struct DemoWordsTests {
    @Test func noShownTextUsesDashesOrExclamationMarksOrGameWords() {
        var texts = [DemoScript.clickCaption(petLabel: "deploy")]
        for scene in DemoScript.scenes {
            if let caption = scene.caption { texts.append(caption) }
            texts.append(contentsOf: scene.stateSlots.map { slot in slot.label })
            for step in scene.steps {
                if case .showTitle(let card) = step.action { texts.append(contentsOf: [card.title, card.subtitle]) }
            }
        }
        for text in texts {
            #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "dash in \(text)")
            #expect(!text.replacingOccurrences(of: "a ! bubble", with: "").contains("!"), "exclamation in \(text)")
            #expect(!text.lowercased().contains("achievement"), "game word in \(text)")
        }
    }
}
