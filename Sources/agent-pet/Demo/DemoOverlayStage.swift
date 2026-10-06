import AgentPetCore
import AppKit

final class DemoPanelWindow {
    private static let fadeSecondsPerUnit: Double = 0.45

    let window: PetWindow
    let view: DemoPanelView
    private(set) var opacity: Double = 0
    private var targetOpacity: Double = 1

    init(view: DemoPanelView, acceptsClicks: Bool) {
        self.view = view
        window = PetWindow(contentRect: CGRect(origin: .zero, size: view.preferredSize), petContentView: view)
        window.ignoresMouseEvents = !acceptsClicks
        window.alphaValue = 0
        window.orderFrontRegardless()
    }

    var isGone: Bool { targetOpacity == 0 && opacity == 0 }

    var isFadingOut: Bool { targetOpacity == 0 }

    func fadeOut() {
        targetOpacity = 0
    }

    func advance(elapsedSeconds: Double) {
        let step = elapsedSeconds / DemoPanelWindow.fadeSecondsPerUnit
        opacity = targetOpacity > opacity ? min(targetOpacity, opacity + step) : max(targetOpacity, opacity - step)
        window.alphaValue = CGFloat(DemoEasing.smooth(opacity))
        if isGone { close() }
    }

    func place(centerX: CGFloat, bottom: CGFloat) {
        let size = view.preferredSize
        window.setFrame(
            CGRect(x: (centerX - size.width / 2).rounded(), y: bottom.rounded(), width: size.width, height: size.height),
            display: true
        )
    }

    func place(topLeft: CGPoint) {
        window.setFrameTopLeftPoint(CGPoint(x: topLeft.x.rounded(), y: topLeft.y.rounded()))
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }
}

enum DemoEasing {
    static func smooth(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}

final class DemoSpriteSheets {
    private let installedLoader: SpritePackLoader
    private let installedRegistry: SpritePackRegistry
    private let shippedRegistry: SpritePackRegistry?
    private let shippedPackNames: Set<String>

    init(installedLoader: SpritePackLoader) {
        self.installedLoader = installedLoader
        installedRegistry = SpritePackRegistry(loader: installedLoader, reportFailure: { _ in })
        _ = installedRegistry.reloadChangedPacks()
        if let shippedDirectory = DemoSpriteDirectories.shippedSpritesDirectory(executablePath: Bundle.main.executablePath) {
            let shippedLoader = SpritePackLoader(packsDirectory: shippedDirectory, extraDirectoryPaths: [])
            let registry = SpritePackRegistry(loader: shippedLoader, reportFailure: { _ in })
            _ = registry.reloadChangedPacks()
            shippedRegistry = registry
            shippedPackNames = Set(shippedLoader.availablePackNames())
        } else {
            shippedRegistry = nil
            shippedPackNames = []
        }
    }

    func sheet(forPackNamed packName: String) -> SpriteSheet {
        if installedLoader.availablePackNames().contains(packName) || !shippedPackNames.contains(packName) {
            return installedRegistry.sheet(forPackNamed: packName)
        }
        return shippedRegistry?.sheet(forPackNamed: packName) ?? installedRegistry.sheet(forPackNamed: packName)
    }

    func tallestInstalledSpriteSideLength() -> CGFloat {
        let packNames = installedLoader.availablePackNames() + [SpritePackLoader.defaultPackName]
        return packNames
            .map { packName in PetGeometry.spritePixelSideLength(frameSize: installedRegistry.sheet(forPackNamed: packName).frameSize) }
            .max() ?? 0
    }

    func mascotImage(forPackNamed packName: String) -> NSImage? {
        let sheet = sheet(forPackNamed: packName)
        guard let frame = sheet.idle.first else { return nil }
        return PixelRenderer.image(for: frame, palette: sheet.palette, scale: PetGeometry.spriteScale, facingLeft: false)
    }
}

final class DemoScreensaverBackdrop {
    private static let fadeSecondsPerUnit: Double = 0.6
    private static let shownAlpha: Double = 0.92

    private let window: PetWindow
    private var opacity: Double = 0
    private(set) var isUp = true

    init(screenFrame: CGRect) {
        let view = DemoBackdropView(frame: CGRect(origin: .zero, size: screenFrame.size))
        window = PetWindow(contentRect: screenFrame, petContentView: view)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        window.setFrame(screenFrame, display: true)
        window.orderFrontRegardless()
    }

    var isGone: Bool { !isUp && opacity == 0 }

    func lower() {
        isUp = false
    }

    func advance(elapsedSeconds: Double) {
        let step = elapsedSeconds / DemoScreensaverBackdrop.fadeSecondsPerUnit
        opacity = isUp ? min(1, opacity + step) : max(0, opacity - step)
        window.alphaValue = CGFloat(DemoEasing.smooth(opacity) * DemoScreensaverBackdrop.shownAlpha)
        if isGone { close() }
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }
}

final class DemoOverlayStage: DemoStage {
    private static let captionBottomAboveGround: CGFloat = 150
    private static let gapAboveDaemonPets: CGFloat = 16
    private static let titleVerticalFraction: CGFloat = 0.55
    private static let captionWidthFraction: CGFloat = 0.9
    private static let homeEasingPerSecond: CGFloat = 3
    private static let stateLabelGap: CGFloat = 12
    private static let captionGapAboveStates: CGFloat = 24
    private static let cursorStartOffset = CGVector(dx: 260, dy: 300)
    private static let cursorFollowPerSecond: CGFloat = 2.2
    private static let cursorPressSeconds: Double = 0.2

    var onPanelClicked: (() -> Void)?

    var hasFocus = true {
        didSet {
            guard hasFocus != oldValue else { return }
            for panel in titlePanels + captionPanels {
                (panel.view as? DemoKeyHintShowing)?.hasFocus = hasFocus
            }
        }
    }

    private let spriteSheets: DemoSpriteSheets
    private let displayChooser: DisplayChooser
    private let groundLift: CGFloat
    private let spriteFrames = PetSpriteFrames()
    private var presencesByPetKey: [String: PetPresence] = [:]
    private var displayedHomeByPetKey: [String: CGFloat] = [:]
    private var titlePanels: [DemoPanelWindow] = []
    private var captionPanels: [DemoPanelWindow] = []
    private var statePanels: [DemoPanelWindow] = []
    private var stateMarks: [DemoStateMark] = []
    private var stateLabelsTop: CGFloat?
    private var terminalPanels: [DemoPanelWindow] = []
    private var cursorPanels: [DemoPanelWindow] = []
    private var cursorTargetSessionId: String?
    private var cursorGoal: CGPoint?
    private var cursorHotspot: CGPoint?
    private var cursorPressSecondsLeft: Double = 0
    private var screensaverBackdrops: [DemoScreensaverBackdrop] = []
    private var screensaverIsUp = false

    init(contracts: AgentPetContracts) {
        spriteSheets = DemoSpriteSheets(installedLoader: contracts.spritePackLoader)
        displayChooser = contracts.displayChooser
        groundLift = PetGeometry.totalHeight(
            spriteSideLength: spriteSheets.tallestInstalledSpriteSideLength(),
            labelPlacement: contracts.configuration.labelPlacement
        ) + DemoOverlayStage.gapAboveDaemonPets
    }

    private var currentScreenFrame: CGRect {
        OverlayScreenFrames.current(chooser: displayChooser).visibleFrame
    }

    private func ground(in screenFrame: CGRect) -> CGFloat {
        screenFrame.minY + PetGeometry.windowBottomInset + groundLift
    }

    var isSettled: Bool {
        screensaverBackdrops.isEmpty && presencesByPetKey.isEmpty && titlePanels.isEmpty && captionPanels.isEmpty && statePanels.isEmpty
            && terminalPanels.isEmpty && cursorPanels.isEmpty
    }

    func present(scene: DemoScene, number: Int, of sceneCount: Int) {}

    func present(title: DemoTitleCard?) {
        if let current = titlePanels.last, let currentView = current.view as? DemoTitleView, currentView.card == title, !current.isGone {
            return
        }
        for panel in titlePanels { panel.fadeOut() }
        guard let title else { return }
        let screenWidth = currentScreenFrame.width
        let panel = clickablePanel(DemoTitleView(card: title, maximumWidth: DemoTitleView.maximumWidth(screenWidth: screenWidth)))
        titlePanels.append(panel)
        placeTitle(panel)
    }

    func present(caption: DemoCaption?) {
        for panel in captionPanels { panel.fadeOut() }
        guard let caption else { return }
        let screenFrame = currentScreenFrame
        let view = DemoCaptionView(caption: caption, maximumWidth: screenFrame.width * DemoOverlayStage.captionWidthFraction)
        let panel = clickablePanel(view)
        captionPanels.append(panel)
        var bottom = ground(in: screenFrame) + DemoOverlayStage.captionBottomAboveGround
        if let stateLabelsTop {
            bottom = max(bottom, stateLabelsTop + DemoOverlayStage.captionGapAboveStates)
        }
        panel.place(centerX: screenFrame.midX, bottom: bottom)
    }

    func present(cursor: DemoCursorCue?) {
        guard let cursor else {
            for panel in cursorPanels { panel.fadeOut() }
            cursorTargetSessionId = nil
            return
        }
        if cursorPanels.last.map({ panel in panel.isFadingOut }) ?? true {
            cursorPanels.append(DemoPanelWindow(view: DemoCursorView(), acceptsClicks: false))
            cursorGoal = nil
            cursorHotspot = nil
        }
        cursorTargetSessionId = cursor.targetSessionId
        if cursor.pressed {
            cursorPressSecondsLeft = DemoOverlayStage.cursorPressSeconds
        }
    }

    func present(terminal: DemoTerminalCard?) {
        for panel in terminalPanels { panel.fadeOut() }
        guard let terminal else { return }
        let panel = clickablePanel(DemoTerminalView(card: terminal, mascot: spriteSheets.mascotImage(forPackNamed: terminal.mascotSprite)))
        terminalPanels.append(panel)
        let screenFrame = currentScreenFrame
        panel.place(
            centerX: screenFrame.midX,
            bottom: screenFrame.minY + screenFrame.height * DemoOverlayStage.titleVerticalFraction - panel.view.preferredSize.height / 2
        )
    }

    func present(screensaver isUp: Bool) {
        guard isUp != screensaverIsUp else { return }
        screensaverIsUp = isUp
        for backdrop in screensaverBackdrops { backdrop.lower() }
        guard isUp else { return }
        screensaverBackdrops.append(DemoScreensaverBackdrop(screenFrame: OverlayScreenFrames.current(chooser: displayChooser).screenFrame))
    }

    func present(states: [DemoStateMark]) {
        for panel in statePanels { panel.fadeOut() }
        stateMarks = states
        stateLabelsTop = nil
        guard !states.isEmpty else { return }
        let screenFrame = currentScreenFrame
        let ground = ground(in: screenFrame)
        let sideLengths = states.map { mark in spriteSideLength(forPackNamed: mark.sprite) }
        let petsHeight = sideLengths.map { side in PetGeometry.totalHeight(spriteSideLength: side, labelPlacement: .pill) }.max() ?? 0
        let laneSpacing = screenFrame.width / CGFloat(states.count + 1)
        let pixelSide = DemoStateLabelView.pixelSide(for: states, laneSpacing: laneSpacing)
        let labelBottom = ground + petsHeight + DemoOverlayStage.stateLabelGap
        for (slotIndex, mark) in states.enumerated() {
            let centerX = LaneLayout.homeHorizontalCenter(laneIndex: slotIndex, laneCount: states.count, screenFrame: screenFrame)
            let label = clickablePanel(DemoStateLabelView(mark: mark, pixelSide: pixelSide))
            label.place(centerX: centerX, bottom: labelBottom)
            statePanels.append(label)
            stateLabelsTop = max(stateLabelsTop ?? 0, labelBottom + label.view.preferredSize.height)
            guard mark.sessionId == nil else { continue }
            let spot = DemoPanelWindow(view: DemoEmptySpotView(sideLength: sideLengths[slotIndex]), acceptsClicks: false)
            spot.place(centerX: centerX, bottom: ground + PetGeometry.spriteBaseline(labelPlacement: .pill))
            statePanels.append(spot)
        }
    }

    func present(pets: [PetDisplayItem], labelPlacement: LabelPlacement) {
        let shownPetKeys = Set(pets.map { item in item.petKey })
        for (petKey, presence) in presencesByPetKey where !shownPetKeys.contains(petKey) {
            presence.animator.requestDive()
        }
        let screenFrame = currentScreenFrame
        for (petIndex, item) in pets.enumerated() {
            let slotIndex = stateMarks.firstIndex { mark in mark.sessionId.map(item.memberSessionIds.contains) ?? false }
            let laneIndex = slotIndex ?? petIndex
            let laneCount = slotIndex == nil ? pets.count : stateMarks.count
            let packName = item.session.sprite ?? SpritePackLoader.defaultPackName
            let spriteSheet = spriteSheets.sheet(forPackNamed: packName)
            let appearance = PetAppearance(
                label: item.label,
                accent: item.session.resolvedAccent,
                mood: item.mood,
                message: item.message,
                bubbleCaption: item.bubbleCaption,
                labelPlacement: labelPlacement,
                spriteSideLength: PetGeometry.spritePixelSideLength(frameSize: spriteSheet.frameSize)
            )
            let presence = presencesByPetKey[item.petKey] ?? makePresence(petKey: item.petKey, appearance: appearance, packName: packName, spriteSheet: spriteSheet)
            presence.animator.requestEmerge()
            presence.view.update(petAppearance: appearance)
            presence.spritePackName = packName
            presence.spriteSheet = spriteSheet
            presence.memberSessionIds = item.memberSessionIds
            presence.homeHorizontalCenter = LaneLayout.homeHorizontalCenter(
                laneIndex: laneIndex,
                laneCount: laneCount,
                screenFrame: screenFrame
            )
            if displayedHomeByPetKey[item.petKey] == nil {
                displayedHomeByPetKey[item.petKey] = presence.homeHorizontalCenter
            }
            presencesByPetKey[item.petKey] = presence
        }
    }

    func advance(elapsedSeconds: Double, sceneProgress: Double) {
        let screenFrame = currentScreenFrame
        for panel in titlePanels { panel.advance(elapsedSeconds: elapsedSeconds) }
        titlePanels.removeAll { panel in panel.isGone }
        for panel in captionPanels {
            panel.advance(elapsedSeconds: elapsedSeconds)
            (panel.view as? DemoCaptionView)?.progress = sceneProgress
        }
        captionPanels.removeAll { panel in panel.isGone }
        for panel in statePanels + terminalPanels + cursorPanels { panel.advance(elapsedSeconds: elapsedSeconds) }
        statePanels.removeAll { panel in panel.isGone }
        terminalPanels.removeAll { panel in panel.isGone }
        cursorPanels.removeAll { panel in panel.isGone }
        for backdrop in screensaverBackdrops { backdrop.advance(elapsedSeconds: elapsedSeconds) }
        screensaverBackdrops.removeAll { backdrop in backdrop.isGone }
        advancePets(elapsedSeconds: elapsedSeconds, screenFrame: screenFrame)
        advanceCursor(elapsedSeconds: elapsedSeconds)
    }

    func tearDown() {
        for presence in presencesByPetKey.values {
            presence.window.orderOut(nil)
            presence.window.close()
        }
        presencesByPetKey.removeAll()
        displayedHomeByPetKey.removeAll()
        for panel in titlePanels + captionPanels + statePanels + terminalPanels + cursorPanels { panel.close() }
        for backdrop in screensaverBackdrops { backdrop.close() }
        screensaverBackdrops.removeAll()
        screensaverIsUp = false
        terminalPanels.removeAll()
        cursorPanels.removeAll()
        cursorTargetSessionId = nil
        titlePanels.removeAll()
        captionPanels.removeAll()
        statePanels.removeAll()
        stateMarks.removeAll()
        stateLabelsTop = nil
    }

    private func clickablePanel(_ view: DemoPanelView) -> DemoPanelWindow {
        (view as? DemoKeyHintShowing)?.hasFocus = hasFocus
        view.onClick = { [weak self] in self?.onPanelClicked?() }
        return DemoPanelWindow(view: view, acceptsClicks: true)
    }

    private func advanceCursor(elapsedSeconds: Double) {
        guard let panel = cursorPanels.last, !panel.isFadingOut else { return }
        if let sessionId = cursorTargetSessionId,
           let presence = presencesByPetKey.values.first(where: { presence in presence.memberSessionIds.contains(sessionId) }) {
            let frame = presence.window.frame
            let spriteSide = PetGeometry.spritePixelSideLength(frameSize: presence.spriteSheet.frameSize)
            cursorGoal = DemoCursorView.aim(petCenterX: frame.midX, petBottom: frame.minY, spriteSideLength: spriteSide)
        }
        guard let goal = cursorGoal else { return }
        let start = cursorHotspot ?? CGPoint(
            x: goal.x + DemoOverlayStage.cursorStartOffset.dx,
            y: goal.y + DemoOverlayStage.cursorStartOffset.dy
        )
        let easing = min(1, DemoOverlayStage.cursorFollowPerSecond * CGFloat(elapsedSeconds))
        let hotspot = CGPoint(x: start.x + (goal.x - start.x) * easing, y: start.y + (goal.y - start.y) * easing)
        cursorHotspot = hotspot
        cursorPressSecondsLeft = max(0, cursorPressSecondsLeft - elapsedSeconds)
        let pressDepth = cursorPressSecondsLeft > 0 ? DemoCursorView.pixelSide : 0
        panel.place(topLeft: CGPoint(x: hotspot.x, y: hotspot.y - pressDepth))
    }

    private func spriteSideLength(forPackNamed packName: String?) -> CGFloat {
        let sheet = spriteSheets.sheet(forPackNamed: packName ?? SpritePackLoader.defaultPackName)
        return PetGeometry.spritePixelSideLength(frameSize: sheet.frameSize)
    }

    private func placeTitle(_ panel: DemoPanelWindow) {
        let screenFrame = currentScreenFrame
        let size = panel.view.preferredSize
        panel.place(
            centerX: screenFrame.midX,
            bottom: screenFrame.minY + screenFrame.height * DemoOverlayStage.titleVerticalFraction - size.height / 2
        )
    }

    private func makePresence(petKey: String, appearance: PetAppearance, packName: String, spriteSheet: SpriteSheet) -> PetPresence {
        let view = PetView(sessionId: petKey, petAppearance: appearance)
        let window = PetWindow(contentRect: CGRect(origin: .zero, size: view.preferredSize), petContentView: view)
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
        return PetPresence(sessionId: petKey, window: window, view: view, spritePackName: packName, spriteSheet: spriteSheet)
    }

    private func advancePets(elapsedSeconds: Double, screenFrame: CGRect) {
        var submergedPetKeys: [String] = []
        let easing = min(1, DemoOverlayStage.homeEasingPerSecond * CGFloat(elapsedSeconds))
        let fullScreenFrame = OverlayScreenFrames.current(chooser: displayChooser).screenFrame
        for (petKey, presence) in presencesByPetKey {
            let displayedHome = displayedHomeByPetKey[petKey] ?? presence.homeHorizontalCenter
            let flying = PetSpaceFlight.advance(
                presence,
                elapsedSeconds: elapsedSeconds,
                floats: screensaverIsUp,
                screenFrame: fullScreenFrame,
                groundBottom: ground(in: screenFrame),
                homeCenterX: displayedHome,
                render: { flyingPresence in self.renderSprite(for: flyingPresence) }
            )
            if flying { continue }
            presence.animator.advance(elapsedSeconds: elapsedSeconds, mood: presence.view.petAppearance.mood)
            if presence.animator.isSubmerged {
                submergedPetKeys.append(petKey)
                continue
            }
            renderSprite(for: presence)
            let easedHome = displayedHome + (presence.homeHorizontalCenter - displayedHome) * easing
            displayedHomeByPetKey[petKey] = easedHome
            place(presence, home: easedHome, screenFrame: screenFrame)
        }
        for petKey in submergedPetKeys {
            guard let presence = presencesByPetKey.removeValue(forKey: petKey) else { continue }
            displayedHomeByPetKey.removeValue(forKey: petKey)
            presence.window.orderOut(nil)
            presence.window.close()
        }
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

    private func place(_ presence: PetPresence, home: CGFloat, screenFrame: CGRect) {
        let windowSize = presence.view.preferredSize
        let desiredCenter = home + presence.animator.horizontalOffsetFromHome
        let horizontalOrigin = min(
            max(desiredCenter - windowSize.width / 2, screenFrame.minX),
            max(screenFrame.maxX - windowSize.width, screenFrame.minX)
        )
        presence.window.setFrame(
            CGRect(
                x: horizontalOrigin.rounded(),
                y: ground(in: screenFrame).rounded(),
                width: windowSize.width,
                height: windowSize.height
            ),
            display: false
        )
    }
}
