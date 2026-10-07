import CoreGraphics
import Foundation
import Testing
import AgentPetCore
@testable import agent_pet

private let tick = 1.0 / 30.0
private let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
private let inset: CGFloat = 4
private let spriteSide: CGFloat = 64
private let shownBar = CGRect(x: 50, y: 7, width: 1628, height: 72)

private func bar(shownFraction: CGFloat) -> CGRect {
    let hiddenOffset = shownBar.maxY + 5
    return shownBar.offsetBy(dx: 0, dy: -hiddenOffset * (1 - shownFraction))
}

private func dockProfile(_ dockBar: CGRect? = shownBar, visibleFrame: CGRect = screenFrame) -> GroundProfile {
    GroundProfile.resolve(standsOnDock: true, screenFrame: screenFrame, visibleFrame: visibleFrame, dockBar: dockBar, bottomInset: inset)
}

private func span(_ centerX: CGFloat) -> ClosedRange<CGFloat> {
    GroundProfile.bodySpan(centerX: centerX, spriteSideLength: spriteSide, bodyWidthFraction: LaneLayout.bodyWidthFraction)
}

private func easeOut(_ progress: Double) -> CGFloat {
    let clamped = min(max(progress, 0), 1)
    return CGFloat(1 - pow(1 - clamped, 3))
}

private func easeIn(_ progress: Double) -> CGFloat {
    let clamped = min(max(progress, 0), 1)
    return CGFloat(clamped * clamped * clamped)
}

@Suite("the ground profile")
struct GroundProfileTests {
    private let top = shownBar.maxY + inset

    @Test func theSettingOffIsTodaysFlatGroundWhateverTheDockDoes() {
        let raisedVisibleFrame = CGRect(x: 0, y: 84, width: 1728, height: 1000)
        for dockBar in [shownBar, bar(shownFraction: 0.5), nil] as [CGRect?] {
            let profile = GroundProfile.resolve(
                standsOnDock: false,
                screenFrame: screenFrame,
                visibleFrame: raisedVisibleFrame,
                dockBar: dockBar,
                bottomInset: inset
            )
            #expect(profile == .flat(base: raisedVisibleFrame.minY + inset))
        }
    }

    @Test func noDockOrADockOnAnotherDisplayLeavesTheGroundFlat() {
        #expect(dockProfile(nil) == .flat(base: inset))
        let otherDisplayBar = shownBar.offsetBy(dx: 3000, dy: 0)
        #expect(dockProfile(otherDisplayBar) == .flat(base: inset))
        let barHighUpTheScreen = shownBar.offsetBy(dx: 0, dy: 600)
        #expect(dockProfile(barHighUpTheScreen) == .flat(base: inset))
    }

    @Test func anAlwaysVisibleDockIsARaisedSegmentOverTheTrueScreenBottom() {
        let raisedVisibleFrame = CGRect(x: 0, y: 84, width: 1728, height: 1000)
        let profile = dockProfile(visibleFrame: raisedVisibleFrame)
        #expect(profile.kind == .dock)
        #expect(profile.base == screenFrame.minY + inset)
        #expect(profile.segment == GroundSegment(minX: shownBar.minX, maxX: shownBar.maxX, top: top))
        #expect(profile.height(over: span(20)) == inset)
        #expect(profile.height(over: span(800)) == top)
        #expect(profile.height(over: span(1720)) == inset)
    }

    @Test func aPetCountsByItsBodyAtAnEdge() {
        let profile = dockProfile()
        let halfBody = spriteSide * LaneLayout.bodyWidthFraction / 2
        #expect(profile.height(over: span(shownBar.minX - halfBody + 1)) == top)
        #expect(profile.height(over: span(shownBar.minX - halfBody)) == inset)
        #expect(profile.height(over: span(shownBar.maxX + halfBody - 1)) == top)
        #expect(profile.height(over: span(shownBar.maxX + halfBody)) == inset)
    }

    @Test func aHiddenDockStillMakesADockProfileWithNothingRaised() {
        let profile = dockProfile(bar(shownFraction: 0))
        #expect(profile.kind == .dock)
        #expect(profile.height(over: span(800)) == inset)
    }
}

private struct Walker {
    var centerX: CGFloat
    var body: GroundBody
    var direction: CGFloat = 1

    init(centerX: CGFloat, profile: GroundProfile) {
        self.centerX = centerX
        body = GroundBody(height: profile.height(over: span(centerX)))
    }

    mutating func step(profile: GroundProfile, walks: Bool = true) {
        if walks {
            let next = centerX + direction * PetAnimator.walkSpeedInPointsPerSecond * CGFloat(tick)
            if body.allowsStep(toGround: profile.height(over: span(next))) { centerX = next }
        }
        body.advance(elapsedSeconds: tick, ground: profile.height(over: span(centerX)))
    }
}

@Suite("the vertical state, stepped at 1/30 s")
struct GroundBodyTests {
    private let top = shownBar.maxY + inset

    @Test func aRisingDockSpringsAPetUpPastItsTopAndItSettlesBackOnIt() {
        var walker = Walker(centerX: 800, profile: dockProfile(bar(shownFraction: 0)))
        #expect(walker.body.height == inset)
        var peak: CGFloat = 0
        var shown: [SpriteAnimationName] = []
        for index in 0..<60 {
            let profile = dockProfile(bar(shownFraction: easeOut(Double(index + 1) * tick / DockSlide.showSeconds)))
            walker.step(profile: profile, walks: false)
            #expect(walker.body.height >= profile.height(over: span(walker.centerX)))
            peak = max(peak, walker.body.height)
            if let animationName = walker.body.animationName, shown.last != animationName { shown.append(animationName) }
        }
        #expect(peak > top + 4)
        #expect(peak < top + GroundBody.maximumSpringSpeed * GroundBody.maximumSpringSpeed / (2 * GroundBody.gravity) + 1)
        #expect(shown == [.jump, .fall])
        #expect(walker.body.height == top)
        #expect(!walker.body.isAirborne)
    }

    @Test func aPetOnTheDockFallsWhenItHidesAndLandsOnTheScreenBottom() {
        var walker = Walker(centerX: 800, profile: dockProfile())
        #expect(walker.body.height == top)
        var sawFall = false
        for index in 0..<60 {
            let profile = dockProfile(bar(shownFraction: 1 - easeIn(Double(index + 1) * tick / DockSlide.hideSeconds)))
            walker.step(profile: profile, walks: false)
            if walker.body.animationName == .fall { sawFall = true }
        }
        #expect(sawFall)
        #expect(walker.body.height == inset)
        #expect(walker.body.animationName == nil)
    }

    @Test func aPetWalksOffTheEdgeOnlyOnceItsBodyIsPastItThenFalls() {
        let profile = dockProfile()
        let halfBody = spriteSide * LaneLayout.bodyWidthFraction / 2
        var walker = Walker(centerX: shownBar.maxX - 10, profile: profile)
        var sawFall = false
        for _ in 0..<150 {
            walker.step(profile: profile)
            if walker.centerX - halfBody < shownBar.maxX { #expect(walker.body.height == top) }
            if walker.body.animationName == .fall { sawFall = true }
        }
        #expect(walker.centerX > shownBar.maxX + halfBody)
        #expect(sawFall)
        #expect(walker.body.height == inset)
    }

    @Test func aPetJumpsUpAnEdgeInItsLaneAndNeverPassesThroughTheDock() {
        let profile = dockProfile()
        var walker = Walker(centerX: shownBar.minX - 60, profile: profile)
        var shown: [SpriteAnimationName] = []
        for _ in 0..<150 {
            walker.step(profile: profile)
            if profile.segment?.overlaps(span(walker.centerX)) == true {
                #expect(walker.body.height >= top - GroundBody.stepUpTolerance)
            }
            if let animationName = walker.body.animationName, shown.last != animationName { shown.append(animationName) }
        }
        #expect(shown == [.jump, .fall])
        #expect(walker.centerX > shownBar.minX + 60)
        #expect(walker.body.height == top)
    }

    @Test func aLedgeTooHighToJumpStopsThePetInsteadOfJumping() {
        let tallBar = CGRect(x: 50, y: 7, width: 400, height: GroundBody.maximumJumpHeight + 40)
        let profile = dockProfile(tallBar)
        var walker = Walker(centerX: tallBar.maxX + 80, profile: profile)
        walker.direction = -1
        for _ in 0..<120 { walker.step(profile: profile) }
        #expect(!walker.body.isAirborne)
        #expect(walker.body.height == inset)
        #expect(profile.segment?.overlaps(span(walker.centerX)) == false)
    }

    @Test func theSettingOffPlacesEveryPetExactlyWhereItStandsToday() {
        var body: GroundBody? = GroundBody(height: 300)
        for (index, visibleBottom) in [CGFloat(0), 84, 84, 40, 0].enumerated() {
            let visibleFrame = CGRect(x: 0, y: visibleBottom, width: 1728, height: 1117 - visibleBottom)
            let profile = GroundProfile.resolve(
                standsOnDock: false,
                screenFrame: screenFrame,
                visibleFrame: visibleFrame,
                dockBar: index.isMultiple(of: 2) ? shownBar : nil,
                bottomInset: PetGeometry.windowBottomInset
            )
            let bottom = GroundPlacement.windowBottom(body: &body, profile: profile, span: span(800), elapsedSeconds: tick)
            #expect(bottom == visibleFrame.minY + PetGeometry.windowBottomInset)
            #expect(body == nil)
        }
    }

    @Test func aHiddenDockLeavesLanesAndWalkingUntouched() {
        let flat = GroundProfile.flat(base: inset)
        let hidden = dockProfile(bar(shownFraction: 0))
        let lanes = LaneLayout.laneCenters(count: 5, screenFrame: screenFrame)
        #expect(lanes == LaneLayout.laneCenters(count: 5, screenFrame: screenFrame))
        var onFlat = Walker(centerX: 100, profile: flat)
        var onHidden = Walker(centerX: 100, profile: hidden)
        for _ in 0..<300 {
            onFlat.step(profile: flat)
            onHidden.step(profile: hidden)
            #expect(onFlat.centerX == onHidden.centerX)
            #expect(onHidden.body.height == inset)
        }
    }

    @Test func thePlacementCreatesABodyStandingOnTheGroundUnderIt() {
        var body: GroundBody?
        let bottom = GroundPlacement.windowBottom(body: &body, profile: dockProfile(), span: span(800), elapsedSeconds: tick)
        #expect(bottom == top)
        #expect(body?.isAirborne == false)
    }
}

private final class FakeDockSensing: DockSensing {
    var dockPreferences = DockPreferences(orientation: .bottom, autohides: true, tileSize: 54, tileCount: 19, separatorCount: 2)
    var listFrame: CGRect?
    var shownOnScreen: Bool? = false
    var pointer = CGPoint(x: 800, y: 600)
    private(set) var preferenceReads = 0
    private(set) var listFrameReads = 0

    func preferences() -> DockPreferences {
        preferenceReads += 1
        return dockPreferences
    }

    func accessibilityListFrame() -> CGRect? {
        listFrameReads += 1
        return listFrame
    }

    func dockIsShownOnScreen() -> Bool? { shownOnScreen }

    func pointerLocation() -> CGPoint { pointer }
}

@Suite("the Dock geometry source")
struct DockGeometrySourceTests {
    private let screens = DockScreens(primaryFrame: screenFrame, dockScreenFrame: screenFrame, allFrames: [screenFrame])

    @Test func theAccessibilityFrameBecomesTheDrawnBarInAppKitCoordinates() {
        let listFrame = DockListFrame.appKitFrame(
            fromAccessibilityFrame: CGRect(x: 76, y: 1033, width: 1576, height: 74),
            primaryScreenHeight: 1117
        )
        #expect(listFrame == CGRect(x: 76, y: 10, width: 1576, height: 74))
        let drawn = DockBarInset.measured.drawnBar(fromListFrame: listFrame)
        #expect(drawn == CGRect(x: 50, y: 7, width: 1628, height: 72))
        #expect(drawn.maxY == listFrame.maxY - 5)
    }

    @Test func theTrackerFollowsTheAccessibilityFrameWhenItIsReadable() {
        let sensing = FakeDockSensing()
        sensing.listFrame = CGRect(x: 76, y: 1117, width: 1576, height: 74)
        var tracker = DockTracker()
        let hidden = tracker.update(now: 0, elapsedSeconds: tick, screens: screens, sensing: sensing)
        #expect(tracker.source == .accessibility)
        #expect(hidden.map { frame in frame.maxY } == -5)
        sensing.listFrame = CGRect(x: 76, y: 1033, width: 1576, height: 74)
        let shown = tracker.update(now: 0.31, elapsedSeconds: tick, screens: screens, sensing: sensing)
        #expect(shown == CGRect(x: 50, y: 7, width: 1628, height: 72))
    }

    @Test func idleReadsAreSlowAndTheEdgeBandOrAChangeMakesThemFast() {
        let sensing = FakeDockSensing()
        sensing.listFrame = CGRect(x: 76, y: 1117, width: 1576, height: 74)
        var tracker = DockTracker()
        for index in 0..<90 {
            _ = tracker.update(now: Double(index) * tick, elapsedSeconds: tick, screens: screens, sensing: sensing)
        }
        #expect(sensing.listFrameReads >= 9 && sensing.listFrameReads <= 11)

        let idleReads = sensing.listFrameReads
        sensing.pointer = CGPoint(x: 800, y: 2)
        for index in 90..<120 {
            _ = tracker.update(now: Double(index) * tick, elapsedSeconds: tick, screens: screens, sensing: sensing)
        }
        #expect(sensing.listFrameReads - idleReads == 30)

        sensing.pointer = CGPoint(x: 800, y: 600)
        sensing.listFrame = CGRect(x: 76, y: 1033, width: 1576, height: 74)
        let beforeChange = sensing.listFrameReads
        for index in 120..<150 {
            _ = tracker.update(now: Double(index) * tick, elapsedSeconds: tick, screens: screens, sensing: sensing)
        }
        #expect(sensing.listFrameReads - beforeChange >= 15)
    }

    @Test func preferencesAreReadOnceEveryFewSeconds() {
        let sensing = FakeDockSensing()
        var tracker = DockTracker()
        for index in 0..<300 {
            _ = tracker.update(now: Double(index) * tick, elapsedSeconds: tick, screens: screens, sensing: sensing)
        }
        #expect(sensing.preferenceReads == 2)
    }

    @Test func withoutAccessTheFreeShownFlagSlidesAnEstimatedBarInAndOut() {
        let sensing = FakeDockSensing()
        var tracker = DockTracker()
        let hidden = tracker.update(now: 0, elapsedSeconds: tick, screens: screens, sensing: sensing)
        #expect(tracker.source == .estimate)
        #expect((hidden?.maxY ?? 0) <= screenFrame.minY)

        sensing.shownOnScreen = true
        var tops: [CGFloat] = []
        for index in 1...12 {
            let estimated = tracker.update(now: 0.4 + Double(index) * tick, elapsedSeconds: tick, screens: screens, sensing: sensing)
            tops.append(estimated?.maxY ?? 0)
        }
        #expect(tops == tops.sorted())
        let expectedTop = DockListFrame.shownBottomGap + 54 + DockListFrame.verticalPadding - DockBarInset.measured.top
        #expect(tops.last == expectedTop)
        #expect((tops.firstIndex(of: expectedTop) ?? 0) >= 5)

        let shownBar = tracker.bar ?? .zero
        #expect(abs(shownBar.midX - screenFrame.midX) < 0.5)
        #expect(shownBar.width > 19 * 54)

        sensing.shownOnScreen = false
        for index in 1...10 {
            _ = tracker.update(now: 1 + Double(index) * tick, elapsedSeconds: tick, screens: screens, sensing: sensing)
        }
        #expect((tracker.bar?.maxY ?? 0) <= screenFrame.minY)
    }

    @Test func anAlwaysVisibleDockIsShownWithoutAskingTheWindowList() {
        let sensing = FakeDockSensing()
        sensing.dockPreferences.autohides = false
        sensing.shownOnScreen = nil
        var tracker = DockTracker()
        let estimated = tracker.update(now: 0, elapsedSeconds: tick, screens: screens, sensing: sensing)
        #expect((estimated?.maxY ?? 0) > 60)
    }

    @Test func aSideDockGivesNoGround() {
        let sensing = FakeDockSensing()
        sensing.dockPreferences.orientation = .left
        sensing.listFrame = CGRect(x: 0, y: 200, width: 74, height: 700)
        var tracker = DockTracker()
        #expect(tracker.update(now: 0, elapsedSeconds: tick, screens: screens, sensing: sensing) == nil)
        #expect(sensing.listFrameReads == 0)
    }
}
