import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import AgentPetCore
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
            if body.allowsStep(toGround: profile.height(over: span(next)), from: profile.height(over: span(centerX))) { centerX = next }
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
        #expect(abs(peak - (top + GroundBody.springOvershoot)) <= 1, "peak \(peak - top) above the top")
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

    @Test func aHopPeaksAtTheEdgePlusItsClearanceWhateverTheStep() {
        let edge = shownBar.maxY + inset
        for step in [1.0 / 30.0, 1.0 / 60.0, 1.0 / 20.0, 1.0 / 144.0] {
            var body = GroundBody(height: inset)
            let stepped = body.allowsStep(toGround: edge)
            #expect(!stepped)
            var apex = body.height
            for _ in 0..<Int(2 / step) {
                body.advance(elapsedSeconds: step, ground: inset)
                apex = max(apex, body.height)
            }
            #expect(abs(apex - (edge + GroundBody.jumpClearance)) <= 1, "step \(step): apex \(apex)")
            #expect(body.height == inset)
        }
    }

    @Test func aSpringPeaksAtItsOvershootAboveTheFinalTopWhateverTheSlideAndStep() {
        let slides: [(Double) -> CGFloat] = [
            { progress in easeOut(progress) },
            { progress in CGFloat(min(max(progress, 0), 1)) },
            { progress in progress <= 0 ? 0 : 1 }
        ]
        for step in [1.0 / 30.0, 1.0 / 60.0] {
            for slide in slides {
                var body = GroundBody(height: inset)
                var apex = body.height
                for index in 0..<Int(1.5 / step) {
                    let shown = slide(Double(index) * step / DockSlide.showSeconds)
                    body.advance(elapsedSeconds: step, ground: max(inset, bar(shownFraction: shown).maxY + inset))
                    apex = max(apex, body.height)
                }
                #expect(abs(apex - (top + GroundBody.springOvershoot)) <= 1, "step \(step): apex \(apex - top) above the top")
                #expect(body.height == top)
            }
        }
    }

    private func launches(_ phases: [GroundBodyPhase]) -> Int {
        zip([GroundBodyPhase.standing] + phases, phases).filter { previous, current in
            previous != .rising && current == .rising
        }.count
    }

    @Test func aStutteredSlideSpringsOnceAndOnlyWhenTheDockHasSettled() {
        var body = GroundBody(height: inset)
        var phases: [GroundBodyPhase] = []
        var floor = inset
        for index in 0..<60 {
            let shown = easeOut(Double(index) * tick / DockSlide.showSeconds)
            if index % 2 == 0 { floor = max(inset, bar(shownFraction: shown).maxY + inset) }
            body.advance(elapsedSeconds: tick, ground: floor)
            phases.append(body.phase)
        }
        #expect(launches(phases) == 1)
        #expect(body.height == top)
    }

    @Test func theRideStartsAtTheHeightBeforeTheTick() {
        var body = GroundBody(height: inset)
        body.advance(elapsedSeconds: tick, ground: inset)
        body.advance(elapsedSeconds: tick, ground: inset + 30)
        #expect(body.phase == .riding(start: inset, stillSeconds: 0))
    }

    @Test func aDockThatHidesMidRideDropsThePetWithoutASpring() {
        var body = GroundBody(height: inset)
        var phases: [GroundBodyPhase] = []
        var apex: CGFloat = 0
        for index in 0..<45 {
            let fraction: CGFloat = index < 4 ? CGFloat(index) / 8 : max(0, CGFloat(8 - index) / 8)
            let floor = max(inset, bar(shownFraction: fraction).maxY + inset)
            body.advance(elapsedSeconds: tick, ground: floor)
            phases.append(body.phase)
            apex = max(apex, body.height - floor)
        }
        #expect(launches(phases) == 0)
        #expect(apex < GroundBody.springOvershoot / 2)
        #expect(body.height == inset)
    }

    @Test func aPetWalkingOffARisingDockFallsWithoutASpring() {
        var walker = Walker(centerX: shownBar.maxX - 4, profile: dockProfile(bar(shownFraction: 0)))
        var phases: [GroundBodyPhase] = []
        for index in 0..<60 {
            let profile = dockProfile(bar(shownFraction: easeOut(Double(index) * tick / 0.6)))
            walker.step(profile: profile)
            phases.append(walker.body.phase)
        }
        #expect(walker.centerX > shownBar.maxX + spriteSide)
        #expect(launches(phases) == 0)
        #expect(walker.body.height == inset)
    }

    @Test func aJumpStartedOnARisingDockLeavesTheRide() {
        var body = GroundBody(height: inset)
        body.advance(elapsedSeconds: tick, ground: inset)
        body.advance(elapsedSeconds: tick, ground: inset + 30)
        let stepped = body.allowsStep(toGround: inset + 80)
        #expect(!stepped)
        #expect(body.phase == .rising)
        #expect(body.animationName == .jump)
        for _ in 0..<60 { body.advance(elapsedSeconds: tick, ground: inset + 80) }
        #expect(body.phase == .standing)
        #expect(!body.isJumping)
    }

    @Test func aSmallRiseCarriesThePetWithoutASpring() {
        var body = GroundBody(height: inset)
        body.advance(elapsedSeconds: tick, ground: inset)
        body.advance(elapsedSeconds: tick, ground: inset + GroundBody.springMinimumRise - 2)
        var apex = body.height
        for _ in 0..<30 {
            body.advance(elapsedSeconds: tick, ground: inset + GroundBody.springMinimumRise - 2)
            apex = max(apex, body.height)
        }
        #expect(apex == inset + GroundBody.springMinimumRise - 2)
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

final class FakeDockSensing: DockSensing {
    var dockPreferences = DockPreferences(orientation: .bottom, autohides: true, tileSize: 54, tileCount: 19, separatorCount: 2)
    var running = true
    var listFrame: CGRect?
    var window: DockWindowState? = DockWindowState(isOnScreen: false, topLeftFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117))
    var pointer = CGPoint(x: 800, y: 600)
    private(set) var preferenceReads = 0
    private(set) var listFrameReads = 0
    private(set) var windowReads = 0

    var reads: Int { preferenceReads + listFrameReads + windowReads }

    func preferences() -> DockPreferences {
        preferenceReads += 1
        return dockPreferences
    }

    func dockIsRunning() -> Bool { running }

    func accessibilityListFrame() -> CGRect? {
        listFrameReads += 1
        return listFrame
    }

    func dockWindow() -> DockWindowState? {
        windowReads += 1
        return window
    }

    func pointerLocation() -> CGPoint { pointer }
}

private let hiddenListFrame = CGRect(x: 76, y: 1117, width: 1576, height: 74)
private let shownListFrame = CGRect(x: 76, y: 1033, width: 1576, height: 74)

@Suite("the Dock geometry source")
struct DockGeometrySourceTests {
    private let screens = DockScreens(primaryFrame: screenFrame, allFrames: [screenFrame])

    private func run(_ tracker: inout DockTracker, _ sensing: FakeDockSensing, ticks: Range<Int>) {
        for index in ticks {
            _ = tracker.update(now: Double(index) * tick, elapsedSeconds: tick, screens: screens, sensing: sensing)
        }
    }

    @Test func theAccessibilityFrameBecomesTheDrawnBarInAppKitCoordinates() {
        let listFrame = DockListFrame.appKitFrame(fromTopLeftFrame: shownListFrame, primaryScreenHeight: 1117)
        #expect(listFrame == CGRect(x: 76, y: 10, width: 1576, height: 74))
        let drawn = DockBarInset.measured.drawnBar(fromListFrame: listFrame)
        #expect(drawn == CGRect(x: 50, y: 7, width: 1628, height: 72))
        #expect(drawn.maxY == listFrame.maxY - 5)
    }

    @Test func theInsetScalesWithTheTileSize() {
        #expect(DockBarInset.scaled(forTileSize: 54) == DockBarInset.measured)
        let large = DockBarInset.scaled(forTileSize: 108)
        #expect(large == DockBarInset(top: 10, sides: -52, bottom: -6))
        #expect(DockBarInset.scaled(forTileSize: 27).sides == -13)
    }

    @Test func theTrackerFollowsTheAccessibilityFrameWhenItIsReadable() {
        let sensing = FakeDockSensing()
        sensing.listFrame = hiddenListFrame
        var tracker = DockTracker()
        let hidden = tracker.update(now: 0, elapsedSeconds: tick, screens: screens, sensing: sensing)
        #expect(tracker.source == .accessibility)
        #expect(hidden.map { frame in frame.maxY } == -5)
        sensing.listFrame = shownListFrame
        let shown = tracker.update(now: 0.31, elapsedSeconds: tick, screens: screens, sensing: sensing)
        #expect(shown == CGRect(x: 50, y: 7, width: 1628, height: 72))
    }

    @Test func aFailedReadKeepsTheLastRealFrameForAGraceThenFallsBackToTheEstimate() {
        let sensing = FakeDockSensing()
        sensing.listFrame = shownListFrame
        var tracker = DockTracker()
        let real = tracker.update(now: 0, elapsedSeconds: tick, screens: screens, sensing: sensing)
        sensing.listFrame = nil
        for index in 1...40 {
            let kept = tracker.update(now: Double(index) * tick, elapsedSeconds: tick, screens: screens, sensing: sensing)
            #expect(kept == real)
            #expect(tracker.source == .accessibility)
        }
        run(&tracker, sensing, ticks: 41..<80)
        #expect(tracker.source == .estimate)
        #expect((tracker.bar?.maxY ?? 0) <= screenFrame.minY)
    }

    @Test func noDockProcessIsNoGroundAndPetsFallRatherThanSpringing() {
        let sensing = FakeDockSensing()
        sensing.listFrame = shownListFrame
        var tracker = DockTracker()
        _ = tracker.update(now: 0, elapsedSeconds: tick, screens: screens, sensing: sensing)
        sensing.running = false
        let readsBefore = sensing.listFrameReads + sensing.windowReads
        let gone = tracker.update(now: tick, elapsedSeconds: tick, screens: screens, sensing: sensing)
        #expect((gone?.maxY ?? 0) < screenFrame.minY)
        #expect(sensing.listFrameReads + sensing.windowReads == readsBefore)
        let profile = dockProfile(gone)
        #expect(profile.height(over: span(800)) == inset)

        sensing.listFrame = nil
        sensing.window = nil
        var fresh = DockTracker()
        let neverSeen = fresh.update(now: 0, elapsedSeconds: tick, screens: screens, sensing: sensing)
        #expect(neverSeen == nil)
    }

    @Test func idleReadsAreSlowAndOnlyTheDocksOwnBandOrAChangeMakesThemFast() {
        let sensing = FakeDockSensing()
        sensing.listFrame = CGRect(x: 600, y: 1117, width: 500, height: 74)
        var tracker = DockTracker()
        run(&tracker, sensing, ticks: 0..<90)
        #expect(sensing.listFrameReads >= 9 && sensing.listFrameReads <= 11)

        var reads = sensing.listFrameReads
        sensing.pointer = CGPoint(x: 10, y: 2)
        run(&tracker, sensing, ticks: 90..<120)
        #expect(sensing.listFrameReads - reads <= 4)

        reads = sensing.listFrameReads
        sensing.pointer = CGPoint(x: 800, y: 2)
        run(&tracker, sensing, ticks: 120..<150)
        #expect(sensing.listFrameReads - reads == 30)

        sensing.pointer = CGPoint(x: 800, y: 600)
        sensing.listFrame = CGRect(x: 600, y: 1033, width: 500, height: 74)
        reads = sensing.listFrameReads
        run(&tracker, sensing, ticks: 150..<180)
        #expect(sensing.listFrameReads - reads >= 15)
    }

    @Test func preferencesAreReadOnceEveryFewSeconds() {
        let sensing = FakeDockSensing()
        var tracker = DockTracker()
        run(&tracker, sensing, ticks: 0..<300)
        #expect(sensing.preferenceReads == 2)
    }

    @Test func withoutAccessTheWindowFlagSlidesAnEstimatedBarInAndOut() {
        let sensing = FakeDockSensing()
        var tracker = DockTracker()
        let hidden = tracker.update(now: 0, elapsedSeconds: tick, screens: screens, sensing: sensing)
        #expect(tracker.source == .estimate)
        #expect((hidden?.maxY ?? 0) <= screenFrame.minY)

        sensing.window = DockWindowState(isOnScreen: true, topLeftFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117))
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

        sensing.window = DockWindowState(isOnScreen: false, topLeftFrame: nil)
        run(&tracker, sensing, ticks: 40..<50)
        #expect((tracker.bar?.maxY ?? 0) <= screenFrame.minY)
    }

    @Test func anAlwaysVisibleDockStillFollowsTheWindowFlagSoAFullScreenSpaceIsFlat() {
        let sensing = FakeDockSensing()
        sensing.dockPreferences.autohides = false
        sensing.window = DockWindowState(isOnScreen: false, topLeftFrame: nil)
        var tracker = DockTracker()
        let estimated = tracker.update(now: 0, elapsedSeconds: tick, screens: screens, sensing: sensing)
        let profile = dockProfile(estimated)
        #expect(profile.height(over: span(800)) == inset)
    }

    @Test func theEstimateSitsOnTheDisplayTheDocksWindowIsOn() {
        let secondScreen = CGRect(x: 1728, y: -200, width: 1920, height: 1080)
        let twoScreens = DockScreens(primaryFrame: screenFrame, allFrames: [screenFrame, secondScreen])
        let sensing = FakeDockSensing()
        let topLeftOfSecond = CGRect(x: 1728, y: 1117 - secondScreen.maxY, width: 1920, height: 1080)
        sensing.window = DockWindowState(isOnScreen: true, topLeftFrame: topLeftOfSecond)
        var tracker = DockTracker()
        for index in 0..<20 {
            _ = tracker.update(now: Double(index) * tick, elapsedSeconds: tick, screens: twoScreens, sensing: sensing)
        }
        let estimated = tracker.bar ?? .zero
        #expect(abs(estimated.midX - secondScreen.midX) < 0.5)
        #expect(estimated.minY > secondScreen.minY - 10 && estimated.maxY < secondScreen.minY + 100)
    }

    @Test func magnificationNeverRaisesOrWidensTheGroundPastTheRestingDock() {
        let sensing = FakeDockSensing()
        sensing.dockPreferences.magnifies = true
        sensing.dockPreferences.tileSize = 64
        sensing.listFrame = CGRect(x: 70, y: 1117 - 10 - 90, width: 1580, height: 90)
        var tracker = DockTracker()
        var resting: CGRect?
        for index in 0...12 {
            resting = tracker.update(now: Double(index) * tick, elapsedSeconds: tick, screens: screens, sensing: sensing)
        }
        sensing.pointer = CGPoint(x: 800, y: 20)
        sensing.listFrame = CGRect(x: 30, y: 1117 - 10 - 150, width: 1668, height: 150)
        let magnified = tracker.update(now: 0.5, elapsedSeconds: tick, screens: screens, sensing: sensing)
        #expect(magnified == resting)

        sensing.pointer = CGPoint(x: 800, y: 600)
        for index in 1...5 {
            let shrinking = tracker.update(now: 0.5 + Double(index) * tick, elapsedSeconds: tick, screens: screens, sensing: sensing)
            #expect(shrinking == resting)
        }
        let trustedAfterAWhile = tracker.update(now: 1.2, elapsedSeconds: tick, screens: screens, sensing: sensing)
        #expect(trustedAfterAWhile?.height == 150 - DockBarInset.scaled(forTileSize: 64).top - DockBarInset.scaled(forTileSize: 64).bottom)

        var neverResting = DockTracker()
        let estimatedSpan = neverResting.update(now: 0, elapsedSeconds: tick, screens: screens, sensing: sensing)
        let inset64 = DockBarInset.scaled(forTileSize: 64)
        #expect(estimatedSpan?.height == inset64.restingHeight(tileSize: 64))
        #expect((estimatedSpan?.width ?? 0) < 1668)
        #expect(abs((estimatedSpan?.midX ?? 0) - (30 + 1668 / 2)) < 0.5)

        sensing.dockPreferences.magnifies = false
        var plain = DockTracker()
        #expect(plain.update(now: 0, elapsedSeconds: tick, screens: screens, sensing: sensing)?.height == 150 - inset64.top - inset64.bottom)
    }

    @Test func theDocksDisplayComesFromItsBottomCentreSoStackedDisplaysAreToldApart() {
        let upper = CGRect(x: 0, y: 1117, width: 1728, height: 1117)
        let stacked = DockScreens(primaryFrame: screenFrame, allFrames: [screenFrame, upper])
        let sensing = FakeDockSensing()
        sensing.listFrame = CGRect(x: 76, y: -84, width: 1576, height: 74)
        var tracker = DockTracker()
        let bar = tracker.update(now: 0, elapsedSeconds: tick, screens: stacked, sensing: sensing)
        #expect(bar.map { frame in frame.minY } == upper.minY + 7)
        var reads = sensing.listFrameReads
        sensing.pointer = CGPoint(x: 800, y: 2)
        for index in 1...30 {
            _ = tracker.update(now: Double(index) * tick, elapsedSeconds: tick, screens: stacked, sensing: sensing)
        }
        #expect(sensing.listFrameReads - reads <= 4)
        reads = sensing.listFrameReads
        sensing.pointer = CGPoint(x: 800, y: upper.minY + 2)
        for index in 31...60 {
            _ = tracker.update(now: Double(index) * tick, elapsedSeconds: tick, screens: stacked, sensing: sensing)
        }
        #expect(sensing.listFrameReads - reads == 30)
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

@Suite("the overlay's ground with a fake Dock")
@MainActor
struct PetGroundTests {
    private let screenFrames = OverlayScreenFrames(visibleFrame: screenFrame, screenFrame: screenFrame)

    private func makePresence(home: CGFloat) -> PetPresence {
        let view = PetView(
            sessionId: "pet-dock",
            petAppearance: PetAppearance(
                label: "dock", accent: .cyan, mood: .ready, message: nil, bubbleCaption: nil,
                labelPlacement: .pill, spriteSideLength: spriteSide
            )
        )
        let window = PetWindow(contentRect: CGRect(origin: .zero, size: view.preferredSize), petContentView: view)
        let presence = PetPresence(
            sessionId: "pet-dock", window: window, view: view,
            spritePackName: "claude", spriteSheet: SpriteSheet.claude8Bit
        )
        presence.homeHorizontalCenter = home
        return presence
    }

    private func makeGround(_ sensing: FakeDockSensing) -> PetGround {
        PetGround { DockGround(sensing: sensing, screenFrames: { [screenFrame] }) }
    }

    private func step(_ presence: PetPresence, ground: PetGround, now: Double, standsOnDock: Bool = true, sawWait: inout Bool) -> CGFloat {
        ground.refresh(standsOnDock: standsOnDock, screenFrames: screenFrames, now: now, elapsedSeconds: tick)
        var waitedThisTick = false
        presence.animator.advance(elapsedSeconds: tick, mood: .ready) { offset in
            let allowed = ground.allowsStep(presence, toOffset: offset)
            if presence.waitsOnJump { waitedThisTick = true }
            return allowed
        }
        if waitedThisTick {
            sawWait = true
            #expect(presence.animator.walkWasBlocked)
            ground.finishStep(presence)
            #expect(!presence.animator.walkWasBlocked)
            #expect(!presence.waitsOnJump)
        } else {
            ground.finishStep(presence)
        }
        let width = presence.view.preferredSize.width
        let center = PetGround.horizontalOrigin(
            desiredCenter: presence.homeHorizontalCenter + presence.animator.horizontalOffsetFromHome,
            windowWidth: width,
            visibleFrame: screenFrame
        ) + width / 2
        return ground.windowBottom(for: presence, standingCenter: center, elapsedSeconds: tick)
    }

    @Test func theKeyOffPathReadsNoDockAndPlacesPetsAsBefore() {
        let sensing = FakeDockSensing()
        sensing.listFrame = shownListFrame
        let ground = makeGround(sensing)
        let presence = makePresence(home: 800)
        var sawWait = false
        for index in 0..<120 {
            let bottom = step(presence, ground: ground, now: Double(index) * tick, standsOnDock: false, sawWait: &sawWait)
            #expect(bottom == screenFrame.minY + PetGeometry.windowBottomInset)
            #expect(presence.groundBody == nil)
        }
        #expect(sensing.reads == 0)
        #expect(!ground.watchesTheDock)
        #expect(ground.profile == .flat(base: screenFrame.minY + PetGeometry.windowBottomInset))
        presence.window.close()
    }

    @Test func aWalkingPetJumpsUpTheEdgeAndItsBlockedWalkIsForgotten() {
        let sensing = FakeDockSensing()
        sensing.listFrame = CGRect(x: 300, y: 1033, width: 600, height: 74)
        let ground = makeGround(sensing)
        let barLeft: CGFloat = 274
        let presence = makePresence(home: barLeft - 40)
        let top = shownBar.maxY + inset
        var sawWait = false
        var stoodOnTop = false
        for index in 0..<240 {
            let bottom = step(presence, ground: ground, now: Double(index) * tick, sawWait: &sawWait)
            let center = presence.homeHorizontalCenter + presence.animator.horizontalOffsetFromHome
            if ground.profile.segment?.overlaps(ground.bodySpan(of: presence, centerX: center)) == true {
                #expect(bottom >= top - GroundBody.stepUpTolerance)
                if bottom == top { stoodOnTop = true }
            }
            if presence.groundBody?.isJumping == true { #expect(!presence.animator.walkWasBlocked) }
        }
        #expect(sawWait)
        #expect(stoodOnTop)
        presence.window.close()
    }

    private func assertOneFallThenGround(_ shown: [SpriteAnimationName], landing: Int?, label: String) {
        let falls = zip([SpriteAnimationName.idle] + shown, shown).filter { previous, current in previous != .fall && current == .fall }.count
        #expect(falls == 1, "\(label): \(shown)")
        let firstJump = shown.firstIndex(of: .jump)
        let firstFall = shown.firstIndex(of: .fall)
        #expect(firstJump != nil && firstFall != nil && firstJump! < firstFall!, "\(label): \(shown)")
        guard let landing else {
            Issue.record("\(label): never landed")
            return
        }
        #expect(shown[landing...].allSatisfy { animation in animation != .jump && animation != .fall }, "\(label): \(shown)")
    }

    @Test func aSpringShowsJumpThenOneFallAndLandsStraightIntoItsGroundAnimation() {
        let sensing = FakeDockSensing()
        sensing.pointer = CGPoint(x: 800, y: 20)
        sensing.listFrame = hiddenListFrame
        let ground = makeGround(sensing)
        let presence = makePresence(home: 800)
        var sawWait = false
        for index in 0..<20 { _ = step(presence, ground: ground, now: Double(index) * tick, sawWait: &sawWait) }
        var shown: [SpriteAnimationName] = []
        var landing: Int?
        for index in 0..<60 {
            let progress = easeOut(Double(index) * tick / DockSlide.showSeconds)
            sensing.listFrame = CGRect(x: 76, y: 1117 - 84 * progress, width: 1576, height: 74)
            _ = step(presence, ground: ground, now: Double(20 + index) * tick, sawWait: &sawWait)
            shown.append(presence.shownAnimationName)
            if landing == nil, shown.contains(.fall), presence.groundBody?.phase == .standing { landing = index }
        }
        assertOneFallThenGround(shown, landing: landing, label: "spring")
        presence.window.close()
    }

    @Test func anEdgeHopShowsJumpThenOneFallAndLandsStraightIntoItsGroundAnimation() {
        let sensing = FakeDockSensing()
        sensing.listFrame = CGRect(x: 300, y: 1033, width: 600, height: 74)
        let ground = makeGround(sensing)
        let presence = makePresence(home: 234)
        var sawWait = false
        var shown: [SpriteAnimationName] = []
        var landing: Int?
        for index in 0..<120 {
            _ = step(presence, ground: ground, now: Double(index) * tick, sawWait: &sawWait)
            shown.append(presence.shownAnimationName)
            if landing == nil, shown.contains(.fall), presence.groundBody?.phase == .standing { landing = index }
        }
        #expect(sawWait)
        assertOneFallThenGround(shown, landing: landing, label: "hop")
        presence.window.close()
    }

    @Test func theStepCheckStandsWhereTheWindowIsClampedNotWhereTheHomeWouldPutIt() {
        let narrowVisibleFrame = CGRect(x: 0, y: 0, width: 1500, height: 1117)
        let presence = makePresence(home: narrowVisibleFrame.maxX - 4)
        let width = presence.view.preferredSize.width
        let clampedCenter = narrowVisibleFrame.maxX - width / 2
        let halfBody = spriteSide * LaneLayout.bodyWidthFraction / 2
        let sensing = FakeDockSensing()
        sensing.listFrame = CGRect(x: clampedCenter + halfBody + 30, y: 1033, width: 60, height: 74)
        let ground = makeGround(sensing)
        ground.refresh(
            standsOnDock: true,
            screenFrames: OverlayScreenFrames(visibleFrame: narrowVisibleFrame, screenFrame: screenFrame),
            now: 0,
            elapsedSeconds: tick
        )
        #expect(ground.profile.segment?.overlaps(ground.bodySpan(of: presence, centerX: presence.homeHorizontalCenter)) == true)
        #expect(ground.profile.segment?.overlaps(ground.bodySpan(of: presence, centerX: clampedCenter)) == false)
        let bottom = ground.windowBottom(for: presence, standingCenter: clampedCenter, elapsedSeconds: tick)
        #expect(bottom == inset)
        #expect(ground.allowsStep(presence, toOffset: 1))
        #expect(presence.groundBody?.isJumping == false)
        presence.window.close()
    }

    @Test func aHiddenDockRefusesNoStepAnywhere() {
        let sensing = FakeDockSensing()
        sensing.listFrame = hiddenListFrame
        let ground = makeGround(sensing)
        ground.refresh(standsOnDock: true, screenFrames: screenFrames, now: 0, elapsedSeconds: tick)
        #expect(ground.profile.kind == .dock)
        let presence = makePresence(home: 0)
        _ = ground.windowBottom(for: presence, standingCenter: 0, elapsedSeconds: tick)
        for offset in stride(from: CGFloat(0), through: screenFrame.maxX, by: 8) {
            #expect(ground.allowsStep(presence, toOffset: offset))
        }
        #expect(presence.groundBody?.isAirborne == false)
        presence.window.close()
    }
}

private let runningApplicationsKey = "runningApplications"

final class FakeDockSystem: DockSystem {
    var processChanges = 0
    var clock: TimeInterval = 0
    var dockProcessIdentifier: pid_t? = 100
    var deadProcessIdentifiers: Set<pid_t> = []
    var windowsByOwner: [pid_t: [CGWindowID]] = [100: [7]]
    var liveWindows: [CGWindowID: DockWindowDescription] = [7: DockWindowDescription(isOnScreen: true, topLeftFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117))]
    var listFramesByProcess: [pid_t: CGRect] = [100: shownListFrame]
    private(set) var lookups = 0
    private(set) var windowSearches = 0
    private(set) var accessibilityProcessIdentifiers: [pid_t] = []

    func uptime() -> TimeInterval { clock }

    func lookUpDockProcessIdentifier() -> pid_t? {
        lookups += 1
        return dockProcessIdentifier
    }

    func isRunning(_ processIdentifier: pid_t) -> Bool {
        !deadProcessIdentifiers.contains(processIdentifier)
    }

    func dockWindowIdentifiers(ownedBy processIdentifier: pid_t) -> [CGWindowID] {
        windowSearches += 1
        return windowsByOwner[processIdentifier] ?? []
    }

    func describeWindows(_ identifiers: [CGWindowID]) -> [DockWindowDescription] {
        identifiers.compactMap { identifier in liveWindows[identifier] }
    }

    func accessibilityListFrame(processIdentifier: pid_t) -> CGRect? {
        accessibilityProcessIdentifiers.append(processIdentifier)
        return listFramesByProcess[processIdentifier]
    }

    func preferences() -> DockPreferences { DockPreferences(autohides: true, tileSize: 54, tileCount: 19, separatorCount: 2) }

    func pointerLocation() -> CGPoint { CGPoint(x: 800, y: 600) }
}

@Suite("the system Dock sensing keeps up with the Dock process")
struct SystemDockSensingTests {
    @Test func aRestartedDockIsFoundWithoutRestartingTheDaemon() {
        let system = FakeDockSystem()
        let sensing = SystemDockSensing(system: system, accessGranted: { true })
        #expect(sensing.accessibilityListFrame() == shownListFrame)
        #expect(sensing.dockWindow()?.isOnScreen == true)

        system.deadProcessIdentifiers = [100]
        system.dockProcessIdentifier = nil
        system.clock = 1
        #expect(!sensing.dockIsRunning())
        #expect(sensing.accessibilityListFrame() == nil)

        system.dockProcessIdentifier = 200
        system.windowsByOwner[200] = [9]
        system.liveWindows[9] = DockWindowDescription(isOnScreen: false, topLeftFrame: nil)
        system.listFramesByProcess[200] = hiddenListFrame
        system.clock = 1.2
        #expect(sensing.accessibilityListFrame() == nil)
        system.clock = 2.3
        #expect(sensing.accessibilityListFrame() == hiddenListFrame)
        #expect(system.accessibilityProcessIdentifiers.last == 200)
        #expect(sensing.dockWindow()?.isOnScreen == false)
    }

    @Test func aChangeInTheRunningApplicationsIsSeenAtOnce() {
        let system = FakeDockSystem()
        let sensing = SystemDockSensing(system: system, accessGranted: { true })
        #expect(sensing.dockIsRunning())
        let lookups = system.lookups
        system.dockProcessIdentifier = 300
        system.listFramesByProcess[300] = hiddenListFrame
        system.processChanges += 1
        #expect(sensing.accessibilityListFrame() == hiddenListFrame)
        #expect(system.lookups == lookups + 1)
    }

    @Test func aDaemonStartedBeforeTheDockFindsItLater() {
        let system = FakeDockSystem()
        system.dockProcessIdentifier = nil
        let sensing = SystemDockSensing(system: system, accessGranted: { true })
        #expect(!sensing.dockIsRunning())
        system.dockProcessIdentifier = 100
        system.clock = 1.5
        #expect(sensing.dockIsRunning())
    }

    @Test func aStaleWindowIdIsSearchedForAgainAtOnce() {
        let system = FakeDockSystem()
        let sensing = SystemDockSensing(system: system, accessGranted: { false })
        #expect(sensing.dockWindow()?.isOnScreen == true)
        #expect(system.windowSearches == 1)
        system.liveWindows[7] = nil
        system.windowsByOwner[100] = [8]
        system.liveWindows[8] = DockWindowDescription(isOnScreen: false, topLeftFrame: nil)
        system.clock = 0.1
        #expect(sensing.dockWindow()?.isOnScreen == false)
        #expect(system.windowSearches == 2)
    }

    @Test func theRunningApplicationsObserverCountsAChange() {
        let system = LiveDockSystem()
        let before = system.processChanges
        let workspace = NSWorkspace.shared
        workspace.willChangeValue(forKey: runningApplicationsKey)
        workspace.didChangeValue(forKey: runningApplicationsKey)
        #expect(system.processChanges > before)
    }

    @Test func withoutTheGrantTheAccessibilityApiIsNeverCalled() {
        let system = FakeDockSystem()
        let sensing = SystemDockSensing(system: system, accessGranted: { false })
        #expect(sensing.accessibilityListFrame() == nil)
        #expect(system.accessibilityProcessIdentifiers.isEmpty)
    }
}
