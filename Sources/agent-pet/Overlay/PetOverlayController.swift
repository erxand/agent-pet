import AppKit

final class PetOverlayController: NSObject, PetViewInteractionHandler {
    private static let reconcileIntervalInSeconds: TimeInterval = 0.3
    private static let livenessIntervalInSeconds: TimeInterval = 5
    private static let animationIntervalInSeconds: TimeInterval = 1.0 / 30.0
    private static let maximumAnimationStepInSeconds: TimeInterval = 0.25
    private static let substituteGroundFrameIndex = 0

    private let store = PetSessionStore()
    private let claudeSessionDirectory = ClaudeSessionDirectory()
    private let spritePackRegistry = SpritePackRegistry()

    private var presencesBySessionId: [String: PetPresence] = [:]
    private var spriteImageCache: [SpriteImageCacheKey: NSImage] = [:]
    private var lastPetSessionsSignature: SessionsDirectorySignature?
    private var lastClaudeSessionsSignature: SessionsDirectorySignature?
    private var lastAnimationTimestamp = Date()
    private var timers: [Timer] = []

    func start() {
        PetPaths.createStateDirectoriesIfNeeded()
        reconcile(forceReload: true)
        scheduleTimers()
    }

    func petViewDidReceiveLeftClick(sessionId: String) {
        SessionFocuser.focus(tmuxTarget: presencesBySessionId[sessionId]?.tmuxTarget)
        PetTurnState.hide(sessionId: sessionId)
        beginDive(sessionId: sessionId)
    }

    func petViewDidReceiveRightClick(sessionId: String) {
        PetTurnState.hide(sessionId: sessionId)
        beginDive(sessionId: sessionId)
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
        if spritePackRegistry.reloadChangedPacks() {
            spriteImageCache.removeAll()
        }
        let petSessionsSignature = SessionsDirectorySignature.current(directory: PetPaths.sessionsDirectory)
        let claudeSessionsSignature = SessionsDirectorySignature.current(
            directory: PetPaths.claudeSessionsDirectory
        )
        let petSessionsChanged = forceReload || petSessionsSignature != lastPetSessionsSignature
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

    private func refreshResolvedLabels() {
        guard !presencesBySessionId.isEmpty else { return }
        let claudeSessions = claudeSessionDirectory.recordsBySessionId()
        let screenFrames = OverlayScreenFrames.current()
        for record in store.list() {
            guard let presence = presencesBySessionId[record.sessionId] else { continue }
            let resolvedLabel = PetLabel.resolve(
                session: record,
                claudeSession: claudeSessions[record.sessionId]
            )
            guard resolvedLabel != presence.view.petAppearance.label else { continue }
            presence.view.update(resolvedLabel: resolvedLabel)
            applyGeometry(to: presence, screenFrames: screenFrames)
        }
    }

    private func applyRecords(_ records: [PetSession]) {
        let claudeSessions = claudeSessionDirectory.recordsBySessionId()
        let displayableRecords = records
            .filter { record in
                record.enabled
                    && record.visible
                    && ProcessLiveness.isAlive(session: record, claudeSession: claudeSessions[record.sessionId])
            }
            .sorted { leftRecord, rightRecord in leftRecord.updatedAt < rightRecord.updatedAt }

        let displayableSessionIds = Set(displayableRecords.map { record in record.sessionId })
        for (sessionId, _) in presencesBySessionId where !displayableSessionIds.contains(sessionId) {
            beginDive(sessionId: sessionId)
        }

        let screenFrames = OverlayScreenFrames.current()
        for (laneIndex, record) in displayableRecords.enumerated() {
            let claudeSession = claudeSessions[record.sessionId]
            let packName = record.sprite ?? SpritePackLoader.defaultPackName
            let spriteSheet = spritePackRegistry.sheet(forPackNamed: packName)
            let petAppearance = PetAppearance(
                label: PetLabel.resolve(session: record, claudeSession: claudeSession),
                accent: record.resolvedAccent,
                mood: record.mood,
                message: record.message,
                spriteSideLength: PetGeometry.spritePixelSideLength(frameSize: spriteSheet.frameSize)
            )
            let presence = presencesBySessionId[record.sessionId]
                ?? makePresence(
                    sessionId: record.sessionId,
                    petAppearance: petAppearance,
                    packName: packName,
                    spriteSheet: spriteSheet
                )
            presence.animator.requestEmerge()
            presence.view.update(petAppearance: petAppearance)
            presence.spritePackName = packName
            presence.spriteSheet = spriteSheet
            presence.tmuxTarget = record.parsedTmuxTarget ?? claudeSession?.tmux.flatMap { rawTarget in
                TmuxTarget(rawValue: rawTarget)
            }
            presence.homeHorizontalCenter = LaneLayout.homeHorizontalCenter(
                laneIndex: laneIndex,
                laneCount: displayableRecords.count,
                screenFrame: screenFrames.visibleFrame
            )
            presencesBySessionId[record.sessionId] = presence
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
        let claudeSessions = claudeSessionDirectory.recordsBySessionId()
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
        guard !presencesBySessionId.isEmpty else { return }

        let screenFrames = OverlayScreenFrames.current()
        var submergedSessionIds: [String] = []
        for presence in presencesBySessionId.values {
            presence.animator.advance(elapsedSeconds: elapsedSeconds, mood: presence.view.petAppearance.mood)
            if presence.animator.isSubmerged {
                submergedSessionIds.append(presence.sessionId)
                continue
            }
            renderSprite(for: presence)
            applyGeometry(to: presence, screenFrames: screenFrames)
        }
        for sessionId in submergedSessionIds {
            removePresence(sessionId: sessionId)
        }
    }

    private func renderSprite(for presence: PetPresence) {
        guard let resolvedAnimation = resolveAnimation(
            presence.animator.animationName,
            in: presence.spriteSheet
        ) else { return }

        let frameIndex = frameIndex(for: presence, resolvedAnimation: resolvedAnimation)
        let accent = presence.view.petAppearance.accent
        let cacheKey = SpriteImageCacheKey(
            packName: presence.spritePackName,
            animationName: resolvedAnimation.animationName,
            frameIndex: frameIndex,
            accent: accent,
            facingLeft: presence.animator.facingLeft
        )

        let spriteImage: NSImage
        if let cachedImage = spriteImageCache[cacheKey] {
            spriteImage = cachedImage
        } else {
            spriteImage = PixelRenderer.image(
                for: resolvedAnimation.frames[frameIndex],
                palette: presence.spriteSheet.palette(accent: accent),
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
