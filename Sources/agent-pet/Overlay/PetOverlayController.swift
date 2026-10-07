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
    private var lanePetKeys: [String] = []
    private var groundPets: [PetPresence] = []
    private var minimumGroundGap: CGFloat = 0
    private var screenChangedSincePlan = false
    private let spriteFrames = PetSpriteFrames()
    private var lastPetSessionsSignature: SessionsDirectorySignature?
    private var lastClaudeSessionsSignature: SessionSourceSignature?
    private let spritePackChanges = DirectoryChangeMonitor()
    private let claudeSessionChanges = DirectoryChangeMonitor()
    private var spritePackRescanGate = RescanGate()
    private let appWindowWatcher = AppWindowWatcher()
    private let stateCommandChanges = DirectoryChangeMonitor()
    private var stateCommandRescanGate = RescanGate()
    private var stateCommands = PetStateSettings.none
    private var effectiveStates = PetEffectiveStates.defaults
    private var petWindowLevel: NSWindow.Level = .screenSaver
    private var claudeSessionRescanGate = RescanGate()
    private var nextSettleDeadline: TimeInterval?
    private var lastAnimationTimestamp = Date()
    private var timers: [Timer] = []
    private var displayChangeObserver: NSObjectProtocol?
    private var homeScreenFrame: CGRect?
    private let dockAccess: DockAccessReporter
    private lazy var ground = PetGround { [weak self] in
        DockGround(sensing: SystemDockSensing { self?.dockAccess.isGranted ?? false })
    }
    private var shutdownCompletion: (() -> Void)?

    var isShuttingDown: Bool { shutdownCompletion != nil }

    init(
        configurationFile: URL = ConfigurationFile.path(),
        store: PetSessionStore = PetSessionStore(),
        spritePackRegistry: SpritePackRegistry = SpritePackRegistry(),
        dockAccess: DockAccessReporter = DockAccessReporter(
            files: .standard,
            access: AccessibilityDockAccess(),
            processIdentifier: ProcessInfo.processInfo.processIdentifier
        )
    ) {
        self.dockAccess = dockAccess
        self.configurationFile = configurationFile
        self.store = store
        self.spritePackRegistry = spritePackRegistry
        contracts = AgentPetContracts(configuration: ConfigurationFile.load(from: configurationFile), focusCompletion: .detaches)
        super.init()
    }

    func start() {
        PetPaths.createStateDirectoriesIfNeeded()
        lastConfigurationModification = ConfigurationFile.modificationDate(of: configurationFile)
        PetStateFile.clearCommands()
        PetStateFile.saveEffective(effectiveStates)
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
        if oldFrame != screenFrames.visibleFrame { screenChangedSincePlan = true }
        refreshGround(screenFrames: screenFrames, elapsedSeconds: nil)
        for presence in presencesBySessionId.values {
            carry(presence, from: oldFrame, to: screenFrames.visibleFrame)
        }
        assignLanes(screenFrame: screenFrames.visibleFrame)
        for presence in presencesBySessionId.values {
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
        guard acceptsInput(forPetKey: petKey) else { return }
        if let focusRequest = presencesBySessionId[petKey]?.focusRequest {
            contracts.focuser.focus(focusRequest)
        }
        hideSession(forPetKey: petKey)
        beginDive(sessionId: petKey)
    }

    func petViewDidReceiveRightClick(sessionId petKey: String) {
        guard acceptsInput(forPetKey: petKey) else { return }
        hideSession(forPetKey: petKey)
        beginDive(sessionId: petKey)
    }

    private func acceptsInput(forPetKey petKey: String) -> Bool {
        PetInputPolicy.acceptsInput(
            input: effectiveStates.input,
            isReturningFromSpace: presencesBySessionId[petKey].map(isReturningFromSpace) ?? false
        )
    }

    private func isReturningFromSpace(_ presence: PetPresence) -> Bool {
        guard let motion = presence.spaceMotion else {
            if presence.walksHomeFromSpace && !presence.animator.isWalkingHome { presence.walksHomeFromSpace = false }
            return presence.walksHomeFromSpace
        }
        switch motion.phase {
        case .floating: return false
        case .falling, .walkingHome, .home: return true
        }
    }

    private func applyInputPolicy(to presence: PetPresence) {
        let inert = !PetInputPolicy.acceptsInput(
            input: effectiveStates.input,
            isReturningFromSpace: isReturningFromSpace(presence)
        )
        guard presence.view.isInert != inert || presence.window.ignoresMouseEvents != inert else { return }
        presence.view.isInert = inert
        presence.window.ignoresMouseEvents = inert
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

    private func updateStates(now: TimeInterval, forced: Bool) -> Bool {
        if stateCommandRescanGate.shouldRescan(changeReported: changeReported(by: stateCommandChanges), forced: forced, now: now) {
            stateCommandChanges.watch(directories: [PetStateFile.controlDirectory])
            stateCommands = PetStateFile.loadCommands()
        }
        var watched = Set(contracts.configuration.fullScreenRules.flatMap { rule in rule.bundleIdentifiers })
        if case .above(let bundleIdentifier) = stateCommands.level {
            watched.insert(bundleIdentifier)
        }
        appWindowWatcher.watch(bundleIdentifiers: watched)
        let summaries = appWindowWatcher.summaries(now: now)
        let resolved = PetEffectiveStates.resolve(
            commands: stateCommands,
            trigger: PetFullScreenRule.triggered(by: contracts.configuration.fullScreenRules, summaries: summaries)
        )
        let level = NSWindow.Level(rawValue: WindowDetection.windowLevel(
            for: resolved.level,
            summaries: summaries,
            petLevel: NSWindow.Level.screenSaver.rawValue,
            shieldingLevel: Int(CGShieldingWindowLevel())
        ))
        let statesChanged = resolved != effectiveStates
        guard statesChanged || level != petWindowLevel else { return false }
        let inputTurnedOff = resolved.input == .off && effectiveStates.input == .on
        let visibilityChanged = resolved.visibility != effectiveStates.visibility
        effectiveStates = resolved
        petWindowLevel = level
        if statesChanged { PetStateFile.saveEffective(resolved) }
        if inputTurnedOff {
            let dropped = RunningFocusCommands.shared.cancelAll()
            if dropped > 0 {
                SpritePackRegistry.writeToStandardError("agent-pet: dropped \(dropped) focus command(s) in flight because input turned off")
            }
        }
        for presence in presencesBySessionId.values {
            presence.window.level = petWindowLevel
            applyInputPolicy(to: presence)
        }
        return visibilityChanged
    }

    private var floatsPets: Bool {
        switch effectiveStates.physics {
        case .float: return true
        case .ground: return false
        }
    }

    private var hidesPets: Bool {
        switch effectiveStates.visibility {
        case .hidden: return true
        case .shown: return false
        }
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
        let now = Date().timeIntervalSince1970
        dockAccess.tick()
        let configurationChanged = reloadConfigurationIfChanged()
        let rescanForced = configurationChanged || forceReload
        let pendingPackIsLocal = spritePackRegistry.hasPendingDownloads && spritePackRegistry.pendingDownloadBecameLocal()
        let spritePackChangeReported = changeReported(by: spritePackChanges) || pendingPackIsLocal
        if spritePackRescanGate.shouldRescan(changeReported: spritePackChangeReported, forced: rescanForced, now: now) {
            spritePackChanges.watch(directories: contracts.spritePackLoader.searchDirectories())
            let replacementLoader = rescanForced ? contracts.spritePackLoader : nil
            if spritePackRegistry.reloadChangedPacks(using: replacementLoader) {
                spriteFrames.removeAllCachedImages()
            }
        }
        var claudeSessionsChanged = false
        if claudeSessionRescanGate.shouldRescan(changeReported: changeReported(by: claudeSessionChanges), forced: rescanForced, now: now) {
            claudeSessionChanges.watch(directories: contracts.sessionSource.watchedDirectories())
            let claudeSessionsSignature = contracts.sessionSource.signature()
            claudeSessionsChanged = claudeSessionsSignature != lastClaudeSessionsSignature
            lastClaudeSessionsSignature = claudeSessionsSignature
        }
        let petSessionsSignature = SessionsDirectorySignature.current(directory: PetPaths.sessionsDirectory)
        let petSessionsChanged = rescanForced || petSessionsSignature != lastPetSessionsSignature
        lastPetSessionsSignature = petSessionsSignature
        let settleDue = nextSettleDeadline.map { deadline in now >= deadline } ?? false
        let visibilityChanged = updateStates(now: now, forced: rescanForced)

        if petSessionsChanged || claudeSessionsChanged || settleDue || visibilityChanged || screenChangedSincePlan {
            applyRecords(store.list(), claudeSessions: currentClaudeSessions())
        }
    }

    private func changeReported(by monitor: DirectoryChangeMonitor) -> Bool {
        monitor.consumeChange() || !monitor.isWatching
    }

    private func currentClaudeSessions() -> [String: ClaudeSessionRecord] {
        guard let lastClaudeSessionsSignature else { return contracts.sessionSource.recordsBySessionId() }
        return contracts.sessionSource.recordsBySessionId(in: lastClaudeSessionsSignature)
    }

    private func applyRecords(_ records: [PetSession], claudeSessions: [String: ClaudeSessionRecord]) {
        let now = Date().timeIntervalSince1970
        let planner = contracts.displayPlanner
        let shownPetKeys = Set(presencesBySessionId.compactMap { petKey, presence in
            presence.animator.isDiving || presence.animator.isSubmerged ? nil : petKey
        })
        let items = hidesPets ? [] : planner.displayItems(
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
        followScreen(to: screenFrames.visibleFrame)
        refreshGround(screenFrames: screenFrames, elapsedSeconds: nil)
        let newcomers = Set(items.map { item in item.petKey }.filter { petKey in presencesBySessionId[petKey] == nil })
        let widthPerPet = LaneLayout.maximumPetWidth(laneCount: items.count, screenFrame: screenFrames.visibleFrame)
        for item in items {
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
                spriteSideLength: PetGeometry.spritePixelSideLength(frameSize: spriteSheet.frameSize),
                feetFlush: contracts.configuration.groundGap != nil
            ).fitted(toWidth: widthPerPet)
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
            presencesBySessionId[item.petKey] = presence
        }
        lanePetKeys = items.map { item in item.petKey }
        assignLanes(newcomers: newcomers, screenFrame: screenFrames.visibleFrame)
        screenChangedSincePlan = false
        for petKey in lanePetKeys {
            guard let presence = presencesBySessionId[petKey] else { continue }
            applyGeometry(to: presence, screenFrames: screenFrames)
        }
    }

    private func followScreen(to visibleFrame: CGRect) {
        defer { homeScreenFrame = visibleFrame }
        guard let oldFrame = homeScreenFrame, oldFrame != visibleFrame else { return }
        screenChangedSincePlan = true
        for presence in presencesBySessionId.values {
            carry(presence, from: oldFrame, to: visibleFrame)
        }
        assignLanes(screenFrame: visibleFrame)
    }

    private func assignLanes(newcomers: Set<String> = [], screenFrame: CGRect) {
        let presences = lanePetKeys.compactMap { petKey in presencesBySessionId[petKey] }
        minimumGroundGap = LaneRedivision.apply(
            to: presences,
            keepingStanding: presences.map { presence in !newcomers.contains(presence.sessionId) },
            screenFrame: screenFrame
        )
        sendCrowdedNeighboursHome()
    }

    private func carry(_ presence: PetPresence, from oldFrame: CGRect, to newFrame: CGRect) {
        presence.groundBody = nil
        LaneRedivision.carry(presence, from: oldFrame, to: newFrame)
    }

    private func sendCrowdedNeighboursHome() {
        sortGroundPets()
        for (left, right) in zip(groundPets, groundPets.dropFirst())
            where groundCenter(of: right) - groundCenter(of: left) < minimumGroundGap {
            left.animator.walkHomeNow()
            right.animator.walkHomeNow()
        }
    }

    private func petLanded(_ presence: PetPresence) {
        presence.walksHomeFromSpace = true
        assignLanes(screenFrame: homeScreenFrame ?? OverlayScreenFrames.current(chooser: contracts.displayChooser).visibleFrame)
    }

    private func collideFloatingPets() {
        guard presencesBySessionId.values.contains(where: { presence in presence.spaceMotion?.phase == .floating }) else { return }
        let floating = presencesBySessionId.values.filter { presence in presence.spaceMotion?.phase == .floating }
        guard floating.count > 1 else { return }
        var motions = floating.compactMap { presence in presence.spaceMotion }
        SpaceMotion.collide(&motions) { first, second in
            (floating[first].view.petAppearance.spriteSideLength + floating[second].view.petAppearance.spriteSideLength)
                / 2 * LaneLayout.bodyWidthFraction
        }
        for (presence, motion) in zip(floating, motions) {
            presence.spaceMotion = motion
        }
    }

    private func sortGroundPets() {
        groundPets.removeAll(keepingCapacity: true)
        for presence in presencesBySessionId.values {
            presence.groundIndex = -1
            guard presence.spaceMotion == nil, !presence.animator.isDiving, !presence.animator.isSubmerged else { continue }
            groundPets.append(presence)
        }
        guard groundPets.count > 1 else { return }
        groundPets.sort { left, right in groundCenter(of: left) < groundCenter(of: right) }
        for (index, presence) in groundPets.enumerated() {
            presence.groundIndex = index
        }
    }

    private func groundCenter(of presence: PetPresence) -> CGFloat {
        presence.homeHorizontalCenter + presence.animator.horizontalOffsetFromHome
    }

    private func allowsStep(_ presence: PetPresence, toOffset offset: CGFloat) -> Bool {
        allowsNeighbourStep(presence, toOffset: offset) && ground.allowsStep(presence, toOffset: offset)
    }

    private func refreshGround(screenFrames: OverlayScreenFrames, elapsedSeconds: Double?) {
        ground.refresh(
            standsOnDock: contracts.configuration.standsOnDock,
            screenFrames: screenFrames,
            now: ProcessInfo.processInfo.systemUptime,
            elapsedSeconds: elapsedSeconds,
            bottomInset: contracts.configuration.groundGap ?? PetGeometry.windowBottomInset
        )
    }

    private func allowsNeighbourStep(_ presence: PetPresence, toOffset offset: CGFloat) -> Bool {
        let index = presence.groundIndex
        guard index >= 0, groundPets.count > 1 else { return true }
        let current = groundCenter(of: presence)
        let next = presence.homeHorizontalCenter + offset
        return allowsStep(presence, from: current, to: next, besideGroundPetAt: index - 1)
            && allowsStep(presence, from: current, to: next, besideGroundPetAt: index + 1)
    }

    private func allowsStep(_ presence: PetPresence, from current: CGFloat, to next: CGFloat, besideGroundPetAt index: Int) -> Bool {
        guard groundPets.indices.contains(index) else { return true }
        let neighbour = groundPets[index]
        guard !LaneLayout.allowsStep(from: current, to: next, neighbour: groundCenter(of: neighbour), minimumGap: minimumGroundGap) else {
            return true
        }
        if presence.animator.isWalkingHome { neighbour.animator.walkHomeNow() }
        return false
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
        window.level = petWindowLevel
        let inert = !PetInputPolicy.acceptsInput(input: effectiveStates.input, isReturningFromSpace: false)
        view.isInert = inert
        window.ignoresMouseEvents = inert
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
        guard let presence = presencesBySessionId[sessionId] else { return }
        if PetChrome.shownOpacity(1, spaceMotion: presence.spaceMotion, hidesLabelsWhileFloating: contracts.configuration.hidesLabelsWhileFloating) == 0 {
            presence.animator.hideChrome()
        }
        presence.animator.requestDive()
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
        followScreen(to: screenFrames.visibleFrame)
        refreshGround(screenFrames: screenFrames, elapsedSeconds: elapsedSeconds)
        var submergedSessionIds: [String] = []
        collideFloatingPets()
        sortGroundPets()
        for presence in presencesBySessionId.values {
            defer { applyInputPolicy(to: presence) }
            if PetSpaceFlight.advance(
                presence,
                elapsedSeconds: elapsedSeconds,
                floats: floatsPets,
                screenFrame: screenFrames.screenFrame,
                groundBottom: ground.floorUnderFlight(of: presence),
                homeCenterX: presence.homeHorizontalCenter,
                render: { flyingPresence in self.renderSprite(for: flyingPresence) },
                landed: { landedPresence in self.petLanded(landedPresence) }
            ) {
                presence.groundBody = nil
                continue
            }
            presence.animator.advance(
                elapsedSeconds: elapsedSeconds,
                mood: presence.view.petAppearance.mood,
                airborne: presence.groundBody?.isAirborne ?? false
            ) { offset in
                self.allowsStep(presence, toOffset: offset)
            }
            ground.finishStep(presence)
            if presence.animator.isSubmerged {
                submergedSessionIds.append(presence.sessionId)
                continue
            }
            // Rendered after the body moves, so a launch or a touchdown tick shows its own state; PetGroundTests.step follows this order.
            if !presence.animator.isDiving {
                applyGeometry(to: presence, screenFrames: screenFrames, elapsedSeconds: elapsedSeconds)
            }
            renderSprite(for: presence)
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
            chromeOpacity: CGFloat(PetChrome.shownOpacity(
                presence.animator.chromeOpacity,
                spaceMotion: presence.spaceMotion,
                hidesLabelsWhileFloating: contracts.configuration.hidesLabelsWhileFloating
            ))
        )
    }

    private func applyGeometry(to presence: PetPresence, screenFrames: OverlayScreenFrames, elapsedSeconds: Double = 0) {
        guard presence.spaceMotion == nil else { return }
        let windowSize = presence.view.preferredSize
        let desiredCenter = presence.homeHorizontalCenter + presence.animator.horizontalOffsetFromHome
        let horizontalOrigin = PetGround.horizontalOrigin(
            desiredCenter: desiredCenter,
            windowWidth: windowSize.width,
            visibleFrame: screenFrames.visibleFrame
        )
        let verticalOrigin = ground.windowBottom(
            for: presence,
            standingCenter: horizontalOrigin + windowSize.width / 2,
            elapsedSeconds: elapsedSeconds
        )

        let frame = CGRect(
            x: horizontalOrigin.rounded(),
            y: verticalOrigin.rounded(),
            width: windowSize.width,
            height: windowSize.height
        )
        guard frame != presence.window.frame else { return }
        presence.window.setFrame(frame, display: false)
    }
}
