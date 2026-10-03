import AgentPetCore
import AppKit

final class PetOverlayController: NSObject, PetViewInteractionHandler {
    private static let reconcileIntervalInSeconds: TimeInterval = 0.3
    private static let livenessIntervalInSeconds: TimeInterval = 5
    private static let animationIntervalInSeconds: TimeInterval = 1.0 / 30.0
    private static let maximumAnimationStepInSeconds: TimeInterval = 0.25
    private static let shutdownDeadlineInSeconds: TimeInterval = 2

    private let store: PetSessionStore
    private let spritePackRegistry: SpritePackRegistry
    private let configurationFile: URL

    private var contracts: AgentPetContracts
    private var lastConfigurationModification: Date?

    private var presencesBySessionId: [String: PetPresence] = [:]
    private let spriteFrames = PetSpriteFrames()
    private var lastPetSessionsSignature: SessionsDirectorySignature?
    private var lastClaudeSessionsSignature: SessionSourceSignature?
    private var nextSettleDeadline: TimeInterval?
    private var lastAnimationTimestamp = Date()
    private var timers: [Timer] = []
    private var displayChangeObserver: NSObjectProtocol?
    private var homeScreenFrame: CGRect?
    private var shutdownCompletion: (() -> Void)?

    var isShuttingDown: Bool { shutdownCompletion != nil }

    init(
        configurationFile: URL = ConfigurationFile.path(),
        store: PetSessionStore = PetSessionStore(),
        spritePackRegistry: SpritePackRegistry = SpritePackRegistry()
    ) {
        self.configurationFile = configurationFile
        self.store = store
        self.spritePackRegistry = spritePackRegistry
        contracts = AgentPetContracts(configuration: ConfigurationFile.load(from: configurationFile), focusCompletion: .detaches)
        super.init()
    }

    func start() {
        PetPaths.createStateDirectoriesIfNeeded()
        lastConfigurationModification = ConfigurationFile.modificationDate(of: configurationFile)
        reconcile(forceReload: true)
        scheduleTimers()
        observeDisplayChanges()
    }

    private func observeDisplayChanges() {
        displayChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.displaysDidChange()
        }
    }

    private func displaysDidChange() {
        guard contracts.configuration.display != .focused else { return }
        let screenFrames = OverlayScreenFrames.current(chooser: contracts.displayChooser)
        let oldFrame = homeScreenFrame ?? screenFrames.visibleFrame
        homeScreenFrame = screenFrames.visibleFrame
        for presence in presencesBySessionId.values {
            presence.homeHorizontalCenter = LaneLayout.carriedHorizontalCenter(
                presence.homeHorizontalCenter,
                from: oldFrame,
                to: screenFrames.visibleFrame
            )
            applyGeometry(to: presence, screenFrames: screenFrames)
        }
    }

    func beginShutdown(completion: @escaping () -> Void) {
        guard !isShuttingDown else { return }
        shutdownCompletion = completion
        for petKey in presencesBySessionId.keys {
            beginDive(sessionId: petKey)
        }
        let deadline = Timer(
            timeInterval: PetOverlayController.shutdownDeadlineInSeconds,
            repeats: false
        ) { [weak self] _ in
            self?.finishShutdown()
        }
        RunLoop.main.add(deadline, forMode: .common)
        finishShutdownIfEveryPetIsUnder()
    }

    private func finishShutdownIfEveryPetIsUnder() {
        guard isShuttingDown, presencesBySessionId.isEmpty else { return }
        finishShutdown()
    }

    private func finishShutdown() {
        guard let completion = shutdownCompletion else { return }
        shutdownCompletion = { }
        completion()
    }

    func petViewDidReceiveLeftClick(sessionId petKey: String) {
        if let focusRequest = presencesBySessionId[petKey]?.focusRequest {
            contracts.focuser.focus(focusRequest)
        }
        hideSession(forPetKey: petKey)
        beginDive(sessionId: petKey)
    }

    func petViewDidReceiveRightClick(sessionId petKey: String) {
        hideSession(forPetKey: petKey)
        beginDive(sessionId: petKey)
    }

    private func hideSession(forPetKey petKey: String) {
        let memberSessionIds = presencesBySessionId[petKey]?.memberSessionIds ?? [petKey]
        for memberSessionId in memberSessionIds {
            PetTurnState.hide(sessionId: memberSessionId)
        }
    }

    private func reloadConfigurationIfChanged() -> Bool {
        let modification = ConfigurationFile.modificationDate(of: configurationFile)
        guard modification != lastConfigurationModification else { return false }
        lastConfigurationModification = modification
        contracts = AgentPetContracts(configuration: ConfigurationFile.load(from: configurationFile), focusCompletion: .detaches)
        return true
    }

    private func scheduleTimers() {
        timers = [
            makeTimer(intervalInSeconds: PetOverlayController.reconcileIntervalInSeconds) { controller in
                controller.reconcile(forceReload: false)
            },
            makeTimer(intervalInSeconds: PetOverlayController.livenessIntervalInSeconds) { controller in
                controller.sweepDeadSessions()
            },
            makeTimer(intervalInSeconds: PetOverlayController.animationIntervalInSeconds) { controller in
                controller.advanceAnimation()
            }
        ]
    }

    private func makeTimer(
        intervalInSeconds: TimeInterval,
        action: @escaping (PetOverlayController) -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: intervalInSeconds, repeats: true) { [weak self] _ in
            guard let self else { return }
            action(self)
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func reconcile(forceReload: Bool) {
        guard !isShuttingDown else { return }
        let configurationChanged = reloadConfigurationIfChanged()
        let replacementLoader = configurationChanged || forceReload ? contracts.spritePackLoader : nil
        if spritePackRegistry.reloadChangedPacks(using: replacementLoader) {
            spriteFrames.removeAllCachedImages()
        }
        let petSessionsSignature = SessionsDirectorySignature.current(directory: PetPaths.sessionsDirectory)
        let claudeSessionsSignature = contracts.sessionSource.signature()
        let petSessionsChanged = forceReload
            || configurationChanged
            || petSessionsSignature != lastPetSessionsSignature
        let claudeSessionsChanged = claudeSessionsSignature != lastClaudeSessionsSignature
        lastPetSessionsSignature = petSessionsSignature
        lastClaudeSessionsSignature = claudeSessionsSignature
        let settleDue = nextSettleDeadline.map { deadline in Date().timeIntervalSince1970 >= deadline } ?? false

        if petSessionsChanged || claudeSessionsChanged || settleDue {
            applyRecords(store.list(), claudeSessions: contracts.sessionSource.recordsBySessionId(in: claudeSessionsSignature))
        }
    }

    private func applyRecords(_ records: [PetSession], claudeSessions: [String: ClaudeSessionRecord]) {
        let now = Date().timeIntervalSince1970
        let planner = contracts.displayPlanner
        let shownPetKeys = Set(presencesBySessionId.compactMap { petKey, presence in
            presence.animator.isDiving || presence.animator.isSubmerged ? nil : petKey
        })
        let items = planner.displayItems(
            records: records,
            claudeSessions: claudeSessions,
            now: now,
            shownPetKeys: shownPetKeys
        )
        nextSettleDeadline = planner.nextSettleDeadline(records: records, now: now)

        let displayablePetKeys = Set(items.map { item in item.petKey })
        for (petKey, _) in presencesBySessionId where !displayablePetKeys.contains(petKey) {
            beginDive(sessionId: petKey)
        }

        let screenFrames = OverlayScreenFrames.current(chooser: contracts.displayChooser)
        homeScreenFrame = screenFrames.visibleFrame
        for (laneIndex, item) in items.enumerated() {
            let record = item.session
            let packName = record.sprite ?? SpritePackLoader.defaultPackName
            let chosenAccent = contracts.configuration.paintsAccentInks
                ? record.chosenAccent(packAccent: spritePackRegistry.ownAccent(forPackNamed: packName))
                : nil
            let sessionSheet = spritePackRegistry.sheet(forPackNamed: packName, chosenAccent: chosenAccent)
            let spriteSheet = sessionSheet.sheet
            let petAppearance = PetAppearance(
                label: item.label,
                accent: record.resolvedAccent,
                mood: item.mood,
                message: item.message,
                bubbleCaption: item.bubbleCaption,
                labelPlacement: contracts.configuration.labelPlacement,
                spriteSideLength: PetGeometry.spritePixelSideLength(frameSize: spriteSheet.frameSize)
            )
            let presence = presencesBySessionId[item.petKey]
                ?? makePresence(
                    sessionId: item.petKey,
                    petAppearance: petAppearance,
                    packName: packName,
                    spriteSheet: spriteSheet
                )
            presence.animator.requestEmerge()
            presence.view.update(petAppearance: petAppearance)
            presence.spritePackName = packName
            presence.spriteSheet = spriteSheet
            presence.spriteTint = sessionSheet.tint
            presence.focusRequest = item.focusRequest
            presence.memberSessionIds = item.memberSessionIds
            presence.homeHorizontalCenter = LaneLayout.homeHorizontalCenter(
                laneIndex: laneIndex,
                laneCount: items.count,
                screenFrame: screenFrames.visibleFrame
            )
            presencesBySessionId[item.petKey] = presence
            applyGeometry(to: presence, screenFrames: screenFrames)
        }
    }

    private func makePresence(
        sessionId: String,
        petAppearance: PetAppearance,
        packName: String,
        spriteSheet: SpriteSheet
    ) -> PetPresence {
        let view = PetView(sessionId: sessionId, petAppearance: petAppearance)
        view.interactionHandler = self
        let window = PetWindow(
            contentRect: CGRect(origin: .zero, size: view.preferredSize),
            petContentView: view
        )
        window.orderFrontRegardless()
        return PetPresence(
            sessionId: sessionId,
            window: window,
            view: view,
            spritePackName: packName,
            spriteSheet: spriteSheet
        )
    }

    private func beginDive(sessionId: String) {
        presencesBySessionId[sessionId]?.animator.requestDive()
    }

    private func removePresence(sessionId: String) {
        guard let presence = presencesBySessionId.removeValue(forKey: sessionId) else { return }
        presence.window.orderOut(nil)
        presence.window.close()
    }

    private func sweepDeadSessions() {
        guard !isShuttingDown else { return }
        let claudeSessions = contracts.sessionSource.recordsBySessionId()
        for record in store.list() {
            let claudeSession = claudeSessions[record.sessionId]
            guard !ProcessLiveness.isAlive(session: record, claudeSession: claudeSession) else { continue }
            store.delete(sessionId: record.sessionId)
            beginDive(sessionId: record.sessionId)
        }
    }

    private func advanceAnimation() {
        let now = Date()
        let elapsedSeconds = min(
            now.timeIntervalSince(lastAnimationTimestamp),
            PetOverlayController.maximumAnimationStepInSeconds
        )
        lastAnimationTimestamp = now
        guard !presencesBySessionId.isEmpty else {
            finishShutdownIfEveryPetIsUnder()
            return
        }

        let screenFrames = OverlayScreenFrames.current(chooser: contracts.displayChooser)
        var submergedSessionIds: [String] = []
        for presence in presencesBySessionId.values {
            presence.animator.advance(elapsedSeconds: elapsedSeconds, mood: presence.view.petAppearance.mood)
            if presence.animator.isSubmerged {
                submergedSessionIds.append(presence.sessionId)
                continue
            }
            renderSprite(for: presence)
            guard !presence.animator.isDiving else { continue }
            applyGeometry(to: presence, screenFrames: screenFrames)
        }
        for sessionId in submergedSessionIds {
            removePresence(sessionId: sessionId)
        }
        finishShutdownIfEveryPetIsUnder()
    }

    private func renderSprite(for presence: PetPresence) {
        guard let spriteImage = spriteFrames.image(for: presence) else { return }
        presence.view.update(
            spriteImage: spriteImage,
            bubbleVerticalOffset: presence.animator.bubbleVerticalOffset,
            groundOffsetFraction: CGFloat(presence.animator.groundOffsetFraction),
            chromeOpacity: CGFloat(presence.animator.chromeOpacity)
        )
    }

    private func applyGeometry(to presence: PetPresence, screenFrames: OverlayScreenFrames) {
        let windowSize = presence.view.preferredSize
        let desiredCenter = presence.homeHorizontalCenter + presence.animator.horizontalOffsetFromHome
        let unclampedHorizontalOrigin = desiredCenter - windowSize.width / 2
        let horizontalOrigin = min(
            max(unclampedHorizontalOrigin, screenFrames.visibleFrame.minX),
            max(screenFrames.visibleFrame.maxX - windowSize.width, screenFrames.visibleFrame.minX)
        )

        let verticalOrigin = screenFrames.visibleFrame.minY + PetGeometry.windowBottomInset

        presence.window.setFrame(
            CGRect(
                x: horizontalOrigin.rounded(),
                y: verticalOrigin.rounded(),
                width: windowSize.width,
                height: windowSize.height
            ),
            display: false
        )
    }
}
