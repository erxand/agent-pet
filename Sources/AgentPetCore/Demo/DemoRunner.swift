import Foundation

package protocol DemoStage: AnyObject {
    var isSettled: Bool { get }
    func present(scene: DemoScene, number: Int, of sceneCount: Int)
    func present(title: DemoTitleCard?)
    func present(caption: DemoCaption?)
    func present(states: [DemoStateMark])
    func present(cursor: DemoCursorCue?)
    func present(terminal: DemoTerminalCard?)
    func present(screensaver isUp: Bool)
    func present(pets: [PetDisplayItem], labelPlacement: LabelPlacement)
    func advance(elapsedSeconds: Double, sceneProgress: Double)
    func tearDown()
}

package final class DemoRunner {
    private static let recordTimeBase: Double = 1_000_000

    private let scenes: [DemoScene]
    private let stage: DemoStage
    private var castBySessionId: [String: PetSession]
    private let cast: [DemoActor]
    private let waitsForUser: Bool
    private let planner = PetDisplayPlanner(grouping: SharedKeyGrouping())

    private(set) var currentSceneIndex = 0
    private(set) var sceneElapsedSeconds: Double = 0
    private(set) var totalElapsedSeconds: Double = 0
    private var sceneStartTotalSeconds: Double = 0
    private(set) var isFinished = false
    package private(set) var isWaitingForUser = false
    private(set) var isTornDown = false
    private var appliedStepCount = 0
    private var hasStarted = false

    package init(scenes: [DemoScene], cast: [DemoActor] = DemoScript.cast, stage: DemoStage, waitsForUser: Bool = false) {
        self.scenes = scenes
        self.cast = cast
        self.stage = stage
        self.waitsForUser = waitsForUser
        castBySessionId = DemoRunner.records(for: cast)
    }

    package var totalDurationInSeconds: Double {
        scenes.reduce(0) { total, scene in total + scene.durationInSeconds }
    }

    package var currentScene: DemoScene? {
        guard !isFinished, scenes.indices.contains(currentSceneIndex) else { return nil }
        return scenes[currentSceneIndex]
    }

    package var displayedPets: [PetDisplayItem] {
        guard currentScene != nil else { return [] }
        return planner.displayItems(records: Array(castBySessionId.values), claudeSessions: [:])
    }

    package func start() {
        guard !hasStarted else { return }
        hasStarted = true
        guard !scenes.isEmpty else {
            finish()
            return
        }
        enterScene(at: 0)
    }

    package func advance(byElapsedSeconds elapsedSeconds: Double) {
        start()
        guard !isFinished, !isTornDown else { return }
        var remainingSeconds = max(0, elapsedSeconds)
        while !isFinished, !isWaitingForUser, let scene = currentScene {
            let sceneLimit = limitInSeconds(of: scene)
            let secondsLeftInScene = sceneLimit - sceneElapsedSeconds
            let stepSeconds = min(remainingSeconds, secondsLeftInScene)
            sceneElapsedSeconds += stepSeconds
            totalElapsedSeconds += stepSeconds
            remainingSeconds -= stepSeconds
            applyDueSteps(of: scene)
            guard sceneElapsedSeconds >= sceneLimit else { break }
            if holdOffsetInSeconds(of: scene) != nil {
                isWaitingForUser = true
                break
            }
            moveToScene(at: currentSceneIndex + 1)
            guard remainingSeconds > 0 else { break }
        }
    }

    package var sceneProgress: Double {
        guard let scene = currentScene, limitInSeconds(of: scene) > 0 else { return 1 }
        return min(1, sceneElapsedSeconds / limitInSeconds(of: scene))
    }

    package func skipToNextScene() {
        start()
        guard !isFinished, !isTornDown, let scene = currentScene else { return }
        totalElapsedSeconds += limitInSeconds(of: scene) - sceneElapsedSeconds
        moveToScene(at: currentSceneIndex + 1)
    }

    package func stop() {
        guard !isTornDown else { return }
        isFinished = true
        isTornDown = true
        stage.tearDown()
    }

    private func moveToScene(at index: Int) {
        guard scenes.indices.contains(index) else {
            finish()
            return
        }
        enterScene(at: index)
    }

    private func enterScene(at index: Int) {
        currentSceneIndex = index
        sceneElapsedSeconds = 0
        sceneStartTotalSeconds = totalElapsedSeconds
        appliedStepCount = 0
        isWaitingForUser = false
        castBySessionId = DemoRunner.records(for: cast)
        let scene = scenes[index]
        stage.present(scene: scene, number: index + 1, of: scenes.count)
        stage.present(title: nil)
        stage.present(cursor: nil)
        stage.present(terminal: nil)
        stage.present(screensaver: false)
        stage.present(states: stateMarks(for: scene))
        stage.present(caption: scene.caption.map { text in
            DemoCaption(text: text, sceneNumber: index + 1, sceneCount: scenes.count, accent: accent(of: scene))
        })
        presentPets(for: scene)
        applyDueSteps(of: scene)
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        isWaitingForUser = false
        castBySessionId = DemoRunner.records(for: cast)
        stage.present(title: nil)
        stage.present(cursor: nil)
        stage.present(terminal: nil)
        stage.present(screensaver: false)
        stage.present(states: [])
        stage.present(caption: nil)
        stage.present(pets: [], labelPlacement: scenes.last?.labelPlacement ?? .pill)
    }

    private func applyDueSteps(of scene: DemoScene) {
        while appliedStepCount < scene.steps.count,
              scene.steps[appliedStepCount].offsetInSeconds <= sceneElapsedSeconds {
            let step = scene.steps[appliedStepCount]
            appliedStepCount += 1
            if apply(step.action, at: step.offsetInSeconds) {
                presentPets(for: scene)
            }
        }
    }

    private func apply(_ action: DemoAction, at offsetInSeconds: Double) -> Bool {
        switch action {
        case .showTitle(let titleCard):
            stage.present(title: titleCard)
            return false
        case .hideTitle:
            stage.present(title: nil)
            return false
        case .show(let actorId, let mood, let message):
            guard castBySessionId[actorId] != nil else { return false }
            castBySessionId[actorId]?.visible = true
            castBySessionId[actorId]?.mood = mood
            castBySessionId[actorId]?.message = message
            castBySessionId[actorId]?.updatedAt = DemoRunner.recordTimeBase + sceneStartTotalSeconds + offsetInSeconds
            return true
        case .hide(let actorIds):
            for actorId in actorIds {
                castBySessionId[actorId]?.visible = false
            }
            return true
        case .pointCursor(let actorId):
            stage.present(cursor: DemoCursorCue(targetSessionId: actorId, pressed: false))
            return false
        case .hideCursor:
            stage.present(cursor: nil)
            return false
        case .showTerminal(let terminalCard):
            stage.present(terminal: terminalCard)
            return false
        case .hideTerminal:
            stage.present(terminal: nil)
            return false
        case .showScreensaver:
            stage.present(screensaver: true)
            return false
        case .hideScreensaver:
            stage.present(screensaver: false)
            return false
        case .click(let actorId):
            stage.present(cursor: DemoCursorCue(targetSessionId: actorId, pressed: true))
            guard let item = displayedPets.first(where: { item in item.memberSessionIds.contains(actorId) }) else {
                return false
            }
            for memberSessionId in item.memberSessionIds {
                castBySessionId[memberSessionId]?.visible = false
            }
            return true
        }
    }

    private func holdOffsetInSeconds(of scene: DemoScene) -> Double? {
        waitsForUser ? scene.holdOffsetInSeconds : nil
    }

    private func limitInSeconds(of scene: DemoScene) -> Double {
        holdOffsetInSeconds(of: scene) ?? scene.durationInSeconds
    }

    private func stateMarks(for scene: DemoScene) -> [DemoStateMark] {
        scene.stateSlots.map { slot in
            let actor = slot.actorId.flatMap { actorId in cast.first { actor in actor.sessionId == actorId } }
            return DemoStateMark(label: slot.label, sessionId: actor?.sessionId, sprite: actor?.sprite, accent: actor?.accent)
        }
    }

    private func accent(of scene: DemoScene) -> AccentColor? {
        for step in scene.steps {
            if case .show(let actorId, _, _) = step.action, let actor = cast.first(where: { actor in actor.sessionId == actorId }) {
                return actor.accent
            }
        }
        return nil
    }

    private func presentPets(for scene: DemoScene) {
        stage.present(pets: displayedPets, labelPlacement: scene.labelPlacement)
    }

    private static func records(for cast: [DemoActor]) -> [String: PetSession] {
        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        var recordsBySessionId: [String: PetSession] = [:]
        for actor in cast {
            var record = PetSession.newlyEnrolled(sessionId: actor.sessionId)
            record.nickname = actor.nickname
            record.sprite = actor.sprite
            record.accent = actor.accent
            record.pid = ownProcessIdentifier
            record.updatedAt = recordTimeBase
            recordsBySessionId[actor.sessionId] = record
        }
        return recordsBySessionId
    }
}
