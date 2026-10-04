import AgentPetCore
import AppKit

final class PetOverlayController: NSObject, PetViewInteractionHandler {
    private static let reconcileIntervalInSeconds: TimeInterval = 0.3
    private static let livenessIntervalInSeconds: TimeInterval = 5
    private static let animationIntervalInSeconds: TimeInterval = 1.0 / 30.0
    private static let maximumAnimationStepInSeconds: TimeInterval = 0.25
    private static let substituteGroundFrameIndex = 0
    // How long a stopping daemon waits for its pets to dive before it exits
    // anyway. A dive is 450 ms; this only matters when the main thread is stuck.
    private static let shutdownDeadlineInSeconds: TimeInterval = 2

    private let store = PetSessionStore()
    private let spritePackRegistry = SpritePackRegistry()
    private let configurationFile = ConfigurationFile.path()

    private var contracts = AgentPetContracts.loaded(focusCompletion: .detaches)
    private var lastConfigurationModification: Date?

    private var presencesBySessionId: [String: PetPresence] = [:]
    private var spriteImageCache: [SpriteImageCacheKey: NSImage] = [:]
    private var lastPetSessionsSignature: SessionsDirectorySignature?
    private var lastClaudeSessionsSignature: SessionSourceSignature?
    private var lastAnimationTimestamp = Date()
    private var timers: [Timer] = []
    private var shutdownCompletion: (() -> Void)?

    var isShuttingDown: Bool { shutdownCompletion != nil }

    func start() {
        PetPaths.createStateDirectoriesIfNeeded()
        lastConfigurationModification = ConfigurationFile.modificationDate(of: configurationFile)
        reconcile(forceReload: true)
        scheduleTimers()
    }

    /// Dives every pet, then calls `completion` once they are all under (or at
    /// the deadline). A daemon stopped by launchd (a restart onto a new build,
    /// an uninstall) used to take its pets off the screen in the same instant;
    /// now they dig back down first. Records are left as they are, so a daemon
    /// that starts again brings the visible ones back up.
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
        contracts = AgentPetContracts.loaded(focusCompletion: .detaches)
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
            spriteImageCache.removeAll()
        }
        let petSessionsSignature = SessionsDirectorySignature.current(directory: PetPaths.sessionsDirectory)
        let claudeSessionsSignature = contracts.sessionSource.signature()
        let petSessionsChanged = forceReload
            || configurationChanged
            || petSessionsSignature != lastPetSessionsSignature
        let claudeSessionsChanged = claudeSessionsSignature != lastClaudeSessionsSignature
        lastPetSessionsSignature = petSessionsSignature
        lastClaudeSessionsSignature = claudeSessionsSignature

        if petSessionsChanged {
            applyRecords(store.list())
            return
        }
        if claudeSessionsChanged {
            refreshResolvedLabels()
        }
    }

    private func displayItems(records: [PetSession]) -> [PetDisplayItem] {
        contracts.displayPlanner.displayItems(
            records: records,
            claudeSessions: contracts.sessionSource.recordsBySessionId()
        )
    }

    private func refreshResolvedLabels() {
        guard !presencesBySessionId.isEmpty else { return }
        let screenFrames = OverlayScreenFrames.current()
        for item in displayItems(records: store.list()) {
            guard let presence = presencesBySessionId[item.petKey] else { continue }
            guard item.label != presence.view.petAppearance.label else { continue }
            presence.view.update(resolvedLabel: item.label)
            applyGeometry(to: presence, screenFrames: screenFrames)
        }
    }

    private func applyRecords(_ records: [PetSession]) {
        let items = displayItems(records: records)

        let displayablePetKeys = Set(items.map { item in item.petKey })
        for (petKey, _) in presencesBySessionId where !displayablePetKeys.contains(petKey) {
            beginDive(sessionId: petKey)
        }

        let screenFrames = OverlayScreenFrames.current()
        for (laneIndex, item) in items.enumerated() {
            let record = item.session
            let packName = record.sprite ?? SpritePackLoader.defaultPackName
            let sessionSheet = spritePackRegistry.sheet(forPackNamed: packName, chosenAccent: record.chosenAccent)
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

        let screenFrames = OverlayScreenFrames.current()
        var submergedSessionIds: [String] = []
        for presence in presencesBySessionId.values {
            presence.animator.advance(elapsedSeconds: elapsedSeconds, mood: presence.view.petAppearance.mood)
            if presence.animator.isSubmerged {
                submergedSessionIds.append(presence.sessionId)
                continue
            }
            renderSprite(for: presence)
            // A diving pet stays where it is. Nothing moves it sideways during
            // a dive, and re-placing it would follow NSScreen.main, which moves
            // to whichever display has keyboard focus: focusing a terminal on
            // another display (one of the things that hides a pet) would carry
            // the pet there to dive, so it vanished from the one being watched.
            guard !presence.animator.isDiving else { continue }
            applyGeometry(to: presence, screenFrames: screenFrames)
        }
        for sessionId in submergedSessionIds {
            removePresence(sessionId: sessionId)
        }
        finishShutdownIfEveryPetIsUnder()
    }

    private func renderSprite(for presence: PetPresence) {
        guard let resolvedAnimation = resolveAnimation(
            presence.animator.animationName,
            in: presence.spriteSheet
        ) else { return }

        let frameIndex = frameIndex(for: presence, resolvedAnimation: resolvedAnimation)
        let cacheKey = SpriteImageCacheKey(
            packName: presence.spritePackName,
            tint: presence.spriteTint,
            animationName: resolvedAnimation.animationName,
            frameIndex: frameIndex,
            facingLeft: presence.animator.facingLeft
        )

        let spriteImage: NSImage
        if let cachedImage = spriteImageCache[cacheKey] {
            spriteImage = cachedImage
        } else {
            spriteImage = PixelRenderer.image(
                for: resolvedAnimation.frames[frameIndex],
                palette: presence.spriteSheet.palette,
                scale: PetGeometry.spriteScale,
                facingLeft: presence.animator.facingLeft
            )
            spriteImageCache[cacheKey] = spriteImage
        }

        presence.view.update(
            spriteImage: spriteImage,
            bubbleVerticalOffset: presence.animator.bubbleVerticalOffset,
            groundOffsetFraction: CGFloat(presence.animator.groundOffsetFraction),
            chromeOpacity: CGFloat(presence.animator.chromeOpacity)
        )
    }

    private func frameIndex(for presence: PetPresence, resolvedAnimation: ResolvedAnimation) -> Int {
        let frameCount = resolvedAnimation.frames.count
        guard presence.animator.playsGroundAnimationOnce else {
            return presence.animator.frameTick % frameCount
        }
        guard resolvedAnimation.animationName == presence.animator.animationName else {
            return PetOverlayController.substituteGroundFrameIndex
        }
        let spreadIndex = Int(presence.animator.groundAnimationProgress * Double(frameCount))
        return min(frameCount - 1, max(0, spreadIndex))
    }

    private struct ResolvedAnimation {
        let animationName: SpriteAnimationName
        let frames: [PixelFrame]
    }

    private func resolveAnimation(
        _ requestedAnimation: SpriteAnimationName,
        in spriteSheet: SpriteSheet
    ) -> ResolvedAnimation? {
        let requestedFrames = requestedAnimation.frames(in: spriteSheet)
        if !requestedFrames.isEmpty {
            return ResolvedAnimation(animationName: requestedAnimation, frames: requestedFrames)
        }
        for fallbackAnimation in SpriteAnimationName.allCases {
            let fallbackFrames = fallbackAnimation.frames(in: spriteSheet)
            if !fallbackFrames.isEmpty {
                return ResolvedAnimation(animationName: fallbackAnimation, frames: fallbackFrames)
            }
        }
        return nil
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
