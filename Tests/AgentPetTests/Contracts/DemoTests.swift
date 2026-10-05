import AppKit
import Foundation
import Testing
@testable import AgentPetCore

final class RecordingDemoFocus: DemoFocus {
    private(set) var takeCount = 0
    private(set) var returnCount = 0

    func takeFocus() { takeCount += 1 }
    func returnFocus() { returnCount += 1 }
}

final class RecordingDemoStage: DemoStage {
    private(set) var presentedPets: [[PetDisplayItem]] = []
    private(set) var titles: [DemoTitleCard?] = []
    private(set) var captions: [DemoCaption?] = []
    private(set) var states: [[DemoStateMark]] = []
    private(set) var events: [String] = []
    private(set) var tearDownCount = 0

    var isSettled: Bool { true }
    func present(scene: DemoScene, number: Int, of sceneCount: Int) {}
    func present(title: DemoTitleCard?) { titles.append(title) }
    func present(caption: DemoCaption?) { captions.append(caption) }
    func present(states: [DemoStateMark]) { self.states.append(states) }
    func present(cursor: DemoCursorCue?) {
        guard let cursor else { return }
        events.append(cursor.pressed ? "press \(cursor.targetSessionId)" : "point \(cursor.targetSessionId)")
    }
    func present(terminal: DemoTerminalCard?) {
        guard let terminal else { return }
        events.append("terminal \(terminal.title)")
    }
    func present(pets: [PetDisplayItem], labelPlacement: LabelPlacement) {
        presentedPets.append(pets)
        events.append("pets " + pets.map { item in item.label }.joined(separator: ","))
    }
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
        #expect(DemoScript.scenes.map { scene in scene.name } == [.title, .states, .click, .finale])
        #expect(DemoScript.totalDurationInSeconds >= 20)
        #expect(DemoScript.totalDurationInSeconds <= 30)
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
                case .show(let actorId, _, _), .click(let actorId), .pointCursor(let actorId):
                    #expect(castIds.contains(actorId))
                case .hide(let actorIds):
                    #expect(actorIds.allSatisfy { actorId in castIds.contains(actorId) })
                case .showTitle, .hideTitle, .hideCursor, .showTerminal, .hideTerminal:
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

    @Test func theStatesSceneShowsTheStatesAUserSeesAtOnce() throws {
        let scene = try #require(DemoScript.scene(named: .states))
        let pets = scene.steps.compactMap { step -> (String, PetMood)? in
            if case .show(let actorId, let mood, _) = step.action { return (actorId, mood) }
            return nil
        }
        let lastShow = try #require(scene.steps.last { step in if case .show = step.action { return true } else { return false } })
        let hide = try #require(scene.steps.first { step in if case .hide = step.action { return true } else { return false } })
        #expect(hide.offsetInSeconds - lastShow.offsetInSeconds >= 7)
        #expect(scene.durationInSeconds >= 8 && scene.durationInSeconds <= 10)
        #expect(scene.caption == "Your pets will appear when your agent is ready and waiting for you.")
        #expect(pets.map { pet in pet.1 } == [.ready, .needsInput])
        #expect(scene.stateSlots.map { slot in slot.label } == ["Ready: turn done", "Needs your input", "Working: no pet"])
        #expect(scene.stateSlots.compactMap { slot in slot.actorId } == pets.map { pet in pet.0 })

        let stage = RecordingDemoStage()
        let states = try runner(for: .states, stage: stage)
        advance(states, by: 2)
        #expect(states.displayedPets.map { item in item.mood } == [.ready, .needsInput])
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

    @Test func theClickSceneShowsACursorClickThenADiveThenASimulatedTerminal() throws {
        let expected = "Clicking the pet brings the terminal tab to focus."
        let scene = try #require(DemoScript.scene(named: .click))
        #expect(scene.caption == expected)
        let stage = RecordingDemoStage()
        let click = try runner(for: .click, stage: stage)
        advance(click, by: 2)
        #expect(click.displayedPets.map { item in item.label } == ["deploy"])
        advance(click, by: 2.5)
        #expect(click.displayedPets.isEmpty)
        let interesting = stage.events.filter { event in event != "pets " }
        #expect(interesting == [
            "pets deploy",
            "point demo-deploy-6e2b",
            "press demo-deploy-6e2b",
            "terminal deploy"
        ])
        let pressIndex = try #require(stage.events.firstIndex(of: "press demo-deploy-6e2b"))
        #expect(stage.events[pressIndex + 1] == "pets ")
        #expect(stage.captions.compactMap { caption in caption?.text } == [expected])
        let hold = try #require(scene.holdOffsetInSeconds)
        let terminalStep = try #require(scene.steps.first { step in if case .showTerminal = step.action { return true } else { return false } })
        #expect(terminalStep.offsetInSeconds < hold)
    }

    @Test func theSimulatedTerminalIsAGenericClaudeCodeSession() throws {
        let scene = try #require(DemoScript.scene(named: .click))
        let card = try #require(scene.steps.compactMap { step -> DemoTerminalCard? in
            if case .showTerminal(let card) = step.action { return card }
            return nil
        }.first)
        #expect(card.title == "deploy")
        #expect(card.productName == "Claude Code")
        #expect(card.mascotSprite == SpritePackLoader.defaultPackName)
        #expect(card.reply == "Deployed. The health check passed.")
        let shown = card.shownTexts.joined(separator: " ").lowercased()
        for forbidden in ["@", "max", "plan", "team", "enterprise", "permission", "bypass", "anthropic", "paramify"] {
            #expect(!shown.contains(forbidden), "terminal shows \(forbidden)")
        }
        for text in card.shownTexts {
            #expect(DemoPixelFont.canRender(text), "cannot draw \(text)")
        }
    }

    @Test func nothingInTheDemoMovesTheSystemCursorOrPostsASystemEvent() throws {
        let demoDirectories = ["Sources/agent-pet/Demo", "Sources/AgentPetCore/Demo"]
        let forbiddenNames = [
            "CGWarpMouseCursorPosition",
            "CGDisplayMoveCursorToPoint",
            "CGAssociateMouseAndMouseCursorPosition",
            "NSCursor",
            "CGEvent",
            "CGPostMouseEvent",
            "CGPostKeyboardEvent",
            ".mouseEvent(",
            ".keyEvent(",
            ".enterExitEvent(",
            "AXUIElementPost",
            "AXUIElementPerformAction",
            "AXUIElementSetAttributeValue",
            "IOHIDPostEvent",
            "NSAppleScript",
            "osascript"
        ]
        var postingFiles: [String] = []
        for directory in demoDirectories {
            let url = Sandbox.packageRoot.appendingPathComponent(directory, isDirectory: true)
            for name in try FileManager.default.contentsOfDirectory(atPath: url.path) where name.hasSuffix(".swift") {
                let source = try String(contentsOf: url.appendingPathComponent(name), encoding: .utf8)
                for forbidden in forbiddenNames {
                    #expect(!source.contains(forbidden), "\(name) uses \(forbidden)")
                }
                if source.contains("postEvent(") {
                    postingFiles.append(name)
                    #expect(source.components(separatedBy: "postEvent(").count == 2, "\(name) posts more than one event")
                    #expect(source.contains("with: .applicationDefined"), "\(name) posts an event that is not app-local")
                }
            }
        }
        #expect(postingFiles == ["DemoApplication.swift"])
    }

    @Test func interactiveScenesHoldUntilSpaceAndOnlyTheTitleMovesByItself() throws {
        let stage = RecordingDemoStage()
        let runner = DemoRunner(scenes: DemoScript.scenes, stage: stage, waitsForUser: true)
        let title = try #require(DemoScript.scene(named: .title))
        #expect(title.holdOffsetInSeconds == nil)
        #expect(title.durationInSeconds >= 5.5 && title.durationInSeconds <= 6.5)
        advance(runner, by: title.durationInSeconds + 0.1)
        #expect(runner.currentScene?.name == .states)
        for scene in DemoScript.scenes.dropFirst() {
            let hold = try #require(scene.holdOffsetInSeconds, "scene \(scene.name.rawValue) has no hold")
            #expect(hold > 0 && hold < scene.durationInSeconds)
            #expect(runner.currentScene?.name == scene.name)
            advance(runner, by: scene.durationInSeconds * 3)
            #expect(runner.currentScene?.name == scene.name, "scene \(scene.name.rawValue) moved on by itself")
            #expect(runner.isWaitingForUser)
            #expect(runner.sceneProgress == 1)
            runner.skipToNextScene()
            #expect(!runner.isWaitingForUser)
        }
        #expect(runner.isFinished)
        #expect(stage.presentedPets.last?.isEmpty == true)
    }

    @Test func aHeldSceneKeepsItsPetsOnScreen() throws {
        let stage = RecordingDemoStage()
        let scene = try #require(DemoScript.scene(named: .states))
        let runner = DemoRunner(scenes: [scene], stage: stage, waitsForUser: true)
        advance(runner, by: 20)
        #expect(runner.displayedPets.count == 2)
    }

    @Test func spaceSkipsTheTitleEarlyAndEscQuitsAndGivesFocusBack() throws {
        let stage = RecordingDemoStage()
        let focus = RecordingDemoFocus()
        let runner = DemoRunner(scenes: DemoScript.scenes, stage: stage, waitsForUser: true)
        var lines: [String] = []
        var exitCode: Int32?
        let playback = DemoPlayback(
            runner: runner,
            stage: stage,
            speed: 1,
            reportStop: { line in lines.append(line) },
            focus: focus,
            onFinish: { code in exitCode = code }
        )
        runner.start()
        #expect(runner.currentScene?.name == .title)
        #expect(playback.handle(key: .space))
        #expect(runner.currentScene?.name == .states)
        #expect(focus.returnCount == 0)
        #expect(playback.handle(key: .escape))
        #expect(exitCode == 0)
        #expect(stage.tearDownCount == 1)
        #expect(focus.returnCount == 1)
        #expect(lines == ["demo stopped by esc. All demo windows are closed."])
        #expect(!playback.handle(key: .space))
        #expect(!playback.handle(key: .escape))
        #expect(focus.returnCount == 1)
    }

    @Test func theKeyHintSaysHowToGetTheKeysBack() {
        #expect(DemoScript.keyHint(hasFocus: true) == "space: next   esc: quit")
        #expect(DemoScript.keyHint(hasFocus: false) == "click here, then press space")
        for hint in [DemoScript.focusedKeyHint, DemoScript.unfocusedKeyHint] {
            #expect(DemoPixelFont.canRender(hint))
            #expect(!hint.contains("\u{2014}") && !hint.contains("\u{2013}") && !hint.contains("!"))
        }
    }

    @Test func onlySpaceAndEscAreDemoKeys() {
        #expect(DemoKey(keyCode: 49) == .space)
        #expect(DemoKey(keyCode: 53) == .escape)
        #expect(DemoKey(keyCode: 36) == nil)
        #expect(DemoKey(keyCode: 0) == nil)
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
        while runner.currentScene?.name != .states {
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
        let states = try runner(for: .states, stage: stage)
        advance(states, by: 2.5)
        states.stop()
        states.stop()
        let presentedCount = stage.presentedPets.count
        advance(states, by: 4)
        states.skipToNextScene()
        #expect(stage.tearDownCount == 1)
        #expect(stage.presentedPets.count == presentedCount)
        #expect(states.isFinished)
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
        var texts: [String] = []
        for scene in DemoScript.scenes {
            if let caption = scene.caption { texts.append(caption) }
            texts.append(contentsOf: scene.stateSlots.map { slot in slot.label })
            for step in scene.steps {
                switch step.action {
                case .showTitle(let card):
                    texts.append(contentsOf: [card.title, card.subtitle])
                case .showTerminal(let card):
                    texts.append(contentsOf: card.shownTexts)
                case .show, .hide, .click, .hideTitle, .pointCursor, .hideCursor, .hideTerminal:
                    break
                }
            }
        }
        texts.append(contentsOf: DemoScript.cast.map { actor in actor.nickname })
        for text in texts {
            #expect(DemoPixelFont.canRender(text), "cannot draw \(text)")
        }
    }

    @Test func wrappingKeepsWordsWholeAndEveryLineInsideTheWidth() {
        let text = "Labels, sprites, colors, how a click focuses, and more. Read Configuration in the README."
        let maximumWidth = DemoPixelFont.width(of: text) / 2
        let lines = DemoPixelFont.wrap(text, maximumWidth: maximumWidth)
        #expect(lines.count == 2)
        #expect(lines.joined(separator: " ") == text)
        #expect(lines.allSatisfy { line in DemoPixelFont.width(of: line) <= maximumWidth })
        #expect(DemoPixelFont.wrap("agent-pet", maximumWidth: 1) == ["agent-pet"])
        #expect(DemoPixelFont.wrap("one two", maximumWidth: 10_000) == ["one two"])
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
        #expect(lines.first?.contains("auto ") == true)
        #expect(lines.dropFirst().dropLast().allSatisfy { line in line.contains("space") })

        let one = try sandbox.run(["demo", "--scene", "click", "--list"])
        #expect(one.standardOutput.split(separator: "\n").first?.hasPrefix("click") == true)

        for removed in ["group", "nametags", "reserved", "climb-out", "needs-input", "lanes", "dive"] {
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
        #expect(run.standardOutput.contains("scene 4/4 finale"))
        #expect(run.standardOutput.contains("title: Configure things to your system,"))
        #expect(!run.standardOutput.contains(" lanes, ") && !run.standardOutput.contains(" dive, "))
        #expect(run.standardOutput.contains("states: Ready: turn done (claude), Needs your input (golem), Working: no pet (no pet)"))
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
        #expect(run.standardOutput.contains("caption: Clicking the pet brings the terminal tab to focus."))
        #expect(run.standardOutput.contains("cursor: clicks demo-deploy-6e2b"))
        #expect(run.standardOutput.contains("terminal: deploy, Claude Code | ~/api | > Deploy the api to staging. | \u{25CF} Deployed. The health check passed."))
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
        var firstOutput = Data()
        while !firstOutput.contains(UInt8(ascii: "\n")) {
            let chunk = outputPipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            firstOutput.append(chunk)
        }
        kill(process.processIdentifier, signalNumber)
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning { process.terminate() }
        let output = String(decoding: firstOutput + outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        #expect(process.terminationReason == .exit)
        #expect(process.terminationStatus == 128 + signalNumber)
        #expect(output.contains("teardown: all demo windows are closed"))
        #expect(output.contains("demo stopped by \(signalName)"))
        #expect(!output.contains("scene 2/4"))
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
        var texts: [String] = []
        for scene in DemoScript.scenes {
            if let caption = scene.caption { texts.append(caption) }
            texts.append(contentsOf: scene.stateSlots.map { slot in slot.label })
            for step in scene.steps {
                if case .showTitle(let card) = step.action { texts.append(contentsOf: [card.title, card.subtitle]) }
                if case .showTerminal(let card) = step.action { texts.append(contentsOf: card.shownTexts) }
            }
        }
        for text in texts {
            #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "dash in \(text)")
            #expect(!text.replacingOccurrences(of: "a ! bubble", with: "").contains("!"), "exclamation in \(text)")
            #expect(!text.lowercased().contains("achievement"), "game word in \(text)")
        }
    }
}
