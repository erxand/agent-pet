import CoreGraphics
import Foundation

package enum DockOrientation: String, Equatable {
    case bottom
    case left
    case right
}

package struct DockPreferences: Equatable {
    package static let domain = "com.apple.dock"
    package static let orientationKey = "orientation"
    package static let autohideKey = "autohide"
    package static let tileSizeKey = "tilesize"
    package static let magnificationKey = "magnification"
    package static let showsRecentsKey = "show-recents"
    package static let persistentAppsKey = "persistent-apps"
    package static let persistentOthersKey = "persistent-others"
    package static let recentAppsKey = "recent-apps"
    package static let defaultTileSize: CGFloat = 48

    package var orientation: DockOrientation
    package var autohides: Bool
    package var tileSize: CGFloat
    package var magnifies: Bool
    package var tileCount: Int
    package var separatorCount: Int

    package init(
        orientation: DockOrientation = .bottom,
        autohides: Bool = false,
        tileSize: CGFloat = DockPreferences.defaultTileSize,
        magnifies: Bool = false,
        tileCount: Int = 0,
        separatorCount: Int = 0
    ) {
        self.orientation = orientation
        self.autohides = autohides
        self.tileSize = tileSize
        self.magnifies = magnifies
        self.tileCount = tileCount
        self.separatorCount = separatorCount
    }
}

package struct DockBarInset: Equatable {
    package static let measuredTileSize: CGFloat = 54
    package static let measured = DockBarInset(top: 5, sides: -26, bottom: -3)

    package let top: CGFloat
    package let sides: CGFloat
    package let bottom: CGFloat

    package init(top: CGFloat, sides: CGFloat, bottom: CGFloat) {
        self.top = top
        self.sides = sides
        self.bottom = bottom
    }

    package static func scaled(forTileSize tileSize: CGFloat) -> DockBarInset {
        let scale = tileSize / measuredTileSize
        return DockBarInset(top: measured.top * scale, sides: measured.sides * scale, bottom: measured.bottom * scale)
    }

    package func drawnBar(fromListFrame listFrame: CGRect) -> CGRect {
        CGRect(
            x: listFrame.minX + sides,
            y: listFrame.minY + bottom,
            width: max(0, listFrame.width - sides * 2),
            height: max(0, listFrame.height - top - bottom)
        )
    }

    package func restingHeight(tileSize: CGFloat) -> CGFloat {
        max(0, tileSize + DockListFrame.verticalPadding - top - bottom)
    }
}

package enum DockListFrame {
    package static let tileSpacing: CGFloat = 4
    package static let endPadding: CGFloat = 8
    package static let verticalPadding: CGFloat = 20
    package static let shownBottomGap: CGFloat = 10
    package static let separatorWidthPerTileSize: CGFloat = 0.48

    package static func appKitFrame(fromTopLeftFrame topLeftFrame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: topLeftFrame.minX,
            y: primaryScreenHeight - topLeftFrame.maxY,
            width: topLeftFrame.width,
            height: topLeftFrame.height
        )
    }

    package static func estimated(preferences: DockPreferences, screenFrame: CGRect, shownFraction: CGFloat) -> CGRect {
        let tiles = CGFloat(max(1, preferences.tileCount))
        let separators = CGFloat(max(0, preferences.separatorCount))
        let width = min(
            screenFrame.width,
            endPadding * 2
                + tiles * (preferences.tileSize + tileSpacing)
                + separators * preferences.tileSize * separatorWidthPerTileSize
        )
        let height = preferences.tileSize + verticalPadding
        let fraction = min(max(shownFraction, 0), 1)
        return CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.minY - height + (height + shownBottomGap) * fraction,
            width: width,
            height: height
        )
    }
}

package struct DockSlide: Equatable {
    package static let showSeconds: Double = 0.23
    package static let hideSeconds: Double = 0.2

    package private(set) var progress: Double

    package init(shown: Bool) {
        progress = shown ? 1 : 0
    }

    package var shownFraction: CGFloat {
        CGFloat(progress * progress * (3 - 2 * progress))
    }

    package var isMoving: Bool { progress > 0 && progress < 1 }

    package mutating func advance(elapsedSeconds: Double, shown: Bool) {
        guard elapsedSeconds > 0 else { return }
        if shown {
            progress = min(1, progress + elapsedSeconds / DockSlide.showSeconds)
        } else {
            progress = max(0, progress - elapsedSeconds / DockSlide.hideSeconds)
        }
    }
}

package struct DockPollCadence: Equatable {
    package static let idleIntervalInSeconds: TimeInterval = 0.3
    package static let activeHoldInSeconds: TimeInterval = 0.6

    private var lastReadAt: TimeInterval?
    private var lastChangeAt: TimeInterval?

    package init() {}

    package func shouldRead(now: TimeInterval, pointerNearDock: Bool) -> Bool {
        guard let lastReadAt else { return true }
        if pointerNearDock { return true }
        if let lastChangeAt, now - lastChangeAt < DockPollCadence.activeHoldInSeconds { return true }
        return now - lastReadAt >= DockPollCadence.idleIntervalInSeconds
    }

    package mutating func recordRead(now: TimeInterval, changed: Bool) {
        lastReadAt = now
        if changed { lastChangeAt = now }
    }
}

package enum DockEdgeBand {
    package static let extraDepth: CGFloat = 30
    package static let sideMargin: CGFloat = 40

    package static func contains(
        _ pointer: CGPoint,
        dockScreen: CGRect,
        dockSpan: ClosedRange<CGFloat>?,
        preferences: DockPreferences
    ) -> Bool {
        let depth = preferences.tileSize + DockListFrame.verticalPadding + extraDepth
        let span = dockSpan ?? dockScreen.minX...dockScreen.maxX
        let left = max(dockScreen.minX, span.lowerBound - sideMargin)
        let right = min(dockScreen.maxX, span.upperBound + sideMargin)
        return pointer.x >= left && pointer.x <= right
            && pointer.y >= dockScreen.minY && pointer.y <= dockScreen.minY + depth
    }
}

package struct DockScreens: Equatable {
    package let primaryFrame: CGRect
    package let allFrames: [CGRect]

    package init(primaryFrame: CGRect, allFrames: [CGRect]) {
        self.primaryFrame = primaryFrame
        self.allFrames = allFrames
    }

    package func screen(containing topLeftWindowFrame: CGRect) -> CGRect? {
        let windowFrame = DockListFrame.appKitFrame(fromTopLeftFrame: topLeftWindowFrame, primaryScreenHeight: primaryFrame.maxY)
        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        return allFrames.first { frame in frame.contains(center) }
    }
}

package struct DockWindowState: Equatable {
    package let isOnScreen: Bool
    package let topLeftFrame: CGRect?

    package init(isOnScreen: Bool, topLeftFrame: CGRect?) {
        self.isOnScreen = isOnScreen
        self.topLeftFrame = topLeftFrame
    }
}

package protocol DockSensing {
    func preferences() -> DockPreferences
    func dockIsRunning() -> Bool
    func accessibilityListFrame() -> CGRect?
    func dockWindow() -> DockWindowState?
    func pointerLocation() -> CGPoint
}

package enum DockBarSource: Equatable {
    case accessibility
    case estimate
}

package struct DockTracker {
    package static let preferencesIntervalInSeconds: TimeInterval = 5
    package static let accessibilityGraceInSeconds: TimeInterval = 1.5
    package static let goneDepth: CGFloat = 5

    package private(set) var bar: CGRect?
    package private(set) var source: DockBarSource?
    private var preferences: DockPreferences?
    private var preferencesReadAt: TimeInterval?
    private var cadence = DockPollCadence()
    private var slide: DockSlide?
    private var estimateShown = false
    private var dockScreen: CGRect?
    private var lastAccessibilityReadAt: TimeInterval?

    package init() {}

    package mutating func update(
        now: TimeInterval,
        elapsedSeconds: Double,
        screens: DockScreens,
        sensing: DockSensing
    ) -> CGRect? {
        let preferences = currentPreferences(now: now, sensing: sensing)
        guard preferences.orientation == .bottom else {
            bar = nil
            source = nil
            slide = nil
            return nil
        }
        guard sensing.dockIsRunning() else {
            lowerBarOutOfSight(screens: screens)
            return bar
        }
        let screen = dockScreen ?? screens.primaryFrame
        let pointerNearDock = DockEdgeBand.contains(
            sensing.pointerLocation(),
            dockScreen: screen,
            dockSpan: bar.map { frame in frame.minX...frame.maxX },
            preferences: preferences
        )
        let slideMoving = slide?.isMoving ?? false
        if slideMoving || cadence.shouldRead(now: now, pointerNearDock: pointerNearDock) {
            read(now: now, elapsedSeconds: elapsedSeconds, preferences: preferences, screens: screens, sensing: sensing)
        } else if source == .estimate {
            advanceEstimate(elapsedSeconds: elapsedSeconds, preferences: preferences, screens: screens)
        }
        return bar
    }

    private mutating func currentPreferences(now: TimeInterval, sensing: DockSensing) -> DockPreferences {
        if let preferences, let preferencesReadAt, now - preferencesReadAt < DockTracker.preferencesIntervalInSeconds {
            return preferences
        }
        let fresh = sensing.preferences()
        preferences = fresh
        preferencesReadAt = now
        return fresh
    }

    private mutating func lowerBarOutOfSight(screens: DockScreens) {
        estimateShown = false
        slide = DockSlide(shown: false)
        guard let current = bar else { return }
        let bottom = (dockScreen ?? screens.primaryFrame).minY
        bar = current.offsetBy(dx: 0, dy: bottom - DockTracker.goneDepth - current.maxY)
    }

    private mutating func read(
        now: TimeInterval,
        elapsedSeconds: Double,
        preferences: DockPreferences,
        screens: DockScreens,
        sensing: DockSensing
    ) {
        let previous = bar
        let inset = DockBarInset.scaled(forTileSize: preferences.tileSize)
        if let accessibilityFrame = sensing.accessibilityListFrame() {
            let listFrame = DockListFrame.appKitFrame(fromTopLeftFrame: accessibilityFrame, primaryScreenHeight: screens.primaryFrame.maxY)
            let drawn = inset.drawnBar(fromListFrame: listFrame)
            bar = capped(drawn, preferences: preferences, inset: inset)
            dockScreen = screens.allFrames.first { frame in drawn.midX >= frame.minX && drawn.midX <= frame.maxX } ?? dockScreen
            source = .accessibility
            slide = nil
            lastAccessibilityReadAt = now
        } else if source == .accessibility, let lastAccessibilityReadAt,
                  now - lastAccessibilityReadAt < DockTracker.accessibilityGraceInSeconds {
            return
        } else {
            if let window = sensing.dockWindow() {
                estimateShown = window.isOnScreen
                if let topLeftFrame = window.topLeftFrame, let screen = screens.screen(containing: topLeftFrame) {
                    dockScreen = screen
                }
            }
            if source != .estimate { slide = DockSlide(shown: estimateShown) }
            source = .estimate
            advanceEstimate(elapsedSeconds: elapsedSeconds, preferences: preferences, screens: screens)
        }
        cadence.recordRead(now: now, changed: previous != nil && bar != previous)
    }

    private mutating func advanceEstimate(elapsedSeconds: Double, preferences: DockPreferences, screens: DockScreens) {
        var moving = slide ?? DockSlide(shown: estimateShown)
        moving.advance(elapsedSeconds: elapsedSeconds, shown: estimateShown)
        slide = moving
        let inset = DockBarInset.scaled(forTileSize: preferences.tileSize)
        let listFrame = DockListFrame.estimated(
            preferences: preferences,
            screenFrame: dockScreen ?? screens.primaryFrame,
            shownFraction: moving.shownFraction
        )
        bar = inset.drawnBar(fromListFrame: listFrame)
    }

    private func capped(_ drawn: CGRect, preferences: DockPreferences, inset: DockBarInset) -> CGRect {
        guard preferences.magnifies else { return drawn }
        var resting = drawn
        resting.size.height = min(drawn.height, inset.restingHeight(tileSize: preferences.tileSize))
        return resting
    }
}
