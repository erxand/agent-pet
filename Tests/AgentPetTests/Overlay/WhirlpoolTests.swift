import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import AgentPetCore
@testable import agent_pet

private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
private let dockListTopLeft = CGRect(x: 76, y: 1033, width: 1576, height: 74)
private let minimizedTileTopLeft = CGRect(x: 1500, y: 1040, width: 60, height: 60)
private let termieTileTopLeft = CGRect(x: 300, y: 1040, width: 60, height: 60)

private func appKitCenter(_ topLeftFrame: CGRect) -> CGPoint {
    let frame = DockListFrame.appKitFrame(fromTopLeftFrame: topLeftFrame, primaryScreenHeight: screen.maxY)
    return CGPoint(x: frame.midX, y: frame.midY)
}

@Suite("the whirlpool finds the window's Dock tile")
struct DockTileLocatorTests {
    private func system(minimizesToApplication: Bool = false, autohides: Bool = false) -> FakeDockSystem {
        let system = FakeDockSystem()
        system.listFramesByProcess = [100: dockListTopLeft]
        system.dockPreferences = DockPreferences(
            autohides: autohides,
            tileSize: 54,
            tileCount: 19,
            separatorCount: 2,
            minimizesToApplication: minimizesToApplication
        )
        system.itemsByProcess[100] = [
            DockItemDescription(subrole: DockItemDescription.applicationSubrole, title: "Termie", topLeftFrame: termieTileTopLeft),
            DockItemDescription(subrole: DockItemDescription.minimizedWindowSubrole, title: "NIST-1025", topLeftFrame: minimizedTileTopLeft)
        ]
        return system
    }

    private func locator(_ system: FakeDockSystem, granted: Bool = true) -> DockTileLocator {
        DockTileLocator(system: system, accessGranted: { granted }, primaryScreenFrame: { screen })
    }

    @Test func theMinimizedTileWinsMatchedWithoutItsStatusGlyph() {
        let location = locator(system()).locate(windowTitle: "✳ NIST-1025", applicationName: "Termie", searchedForSeconds: 0)
        #expect(location == DockTileLocation(center: appKitCenter(minimizedTileTopLeft), source: .minimizedTile, isFinal: true))
    }

    @Test func minimizeIntoTheApplicationIconGoesToTheAppsTile() {
        let location = locator(system(minimizesToApplication: true))
            .locate(windowTitle: "NIST-1025", applicationName: "Termie", searchedForSeconds: 0)
        #expect(location == DockTileLocation(center: appKitCenter(termieTileTopLeft), source: .applicationTile, isFinal: true))
    }

    @Test func aTileNotThereYetIsSearchedForUpToTheLimitThenEstimated() {
        let missing = system()
        missing.itemsByProcess[100] = []
        let early = locator(missing).locate(windowTitle: "NIST-1025", applicationName: nil, searchedForSeconds: 0.4)
        #expect(early.source == .estimate)
        #expect(!early.isFinal)
        let late = locator(missing).locate(windowTitle: "NIST-1025", applicationName: nil, searchedForSeconds: DockTileLocator.tileSearchSeconds)
        #expect(late.source == .estimate)
        #expect(late.isFinal)
        let listFrame = DockListFrame.appKitFrame(fromTopLeftFrame: dockListTopLeft, primaryScreenHeight: screen.maxY)
        #expect(late.center.x > listFrame.midX)
        #expect(late.center.x < listFrame.maxX)
    }

    @Test func withoutAccessibilityTheEstimateIsAllThereIs() {
        let location = locator(system(), granted: false).locate(windowTitle: "NIST-1025", applicationName: "Termie", searchedForSeconds: 0)
        #expect(location.source == .estimate)
        #expect(location.isFinal)
        #expect(location.center == DockTileEstimate.minimizedTileCenter(
            preferences: system().dockPreferences,
            screenFrame: screen,
            listFrame: nil
        ))
    }

    @Test func anApplicationTileThatIsMissingFallsBackToTheEstimate() {
        let location = locator(system(minimizesToApplication: true))
            .locate(windowTitle: "NIST-1025", applicationName: "Other", searchedForSeconds: 0)
        #expect(location.source == .estimate)
        #expect(location.isFinal)
    }

    @Test func aHiddenDockIsEstimatedWhereItWouldBe() {
        let preferences = DockPreferences(autohides: true, tileSize: 54, tileCount: 19, separatorCount: 2)
        let offScreenList = CGRect(x: 76, y: -80, width: 1576, height: 74)
        let center = DockTileEstimate.minimizedTileCenter(preferences: preferences, screenFrame: screen, listFrame: offScreenList)
        #expect(center.y > screen.minY)
        #expect(center.x < offScreenList.maxX)
    }

    @Test func aSideDockPutsTheTileAtItsBottomEnd() {
        let left = DockTileEstimate.minimizedTileCenter(
            preferences: DockPreferences(orientation: .left, tileSize: 54, tileCount: 19),
            screenFrame: screen,
            listFrame: nil
        )
        #expect(left.x < screen.midX)
        #expect(left.y < screen.midY)
        let right = DockTileEstimate.minimizedTileCenter(
            preferences: DockPreferences(orientation: .right, tileSize: 54, tileCount: 19),
            screenFrame: screen,
            listFrame: nil
        )
        #expect(right.x > screen.midX)
    }

    @Test func titlesCompareWithoutLeadingGlyphs() {
        #expect(DockTileLocator.comparableTitle("✳ NIST-1025 ") == "NIST-1025")
        #expect(DockTileLocator.comparableTitle("⠂ Tax questions") == "Tax questions")
        #expect(DockTileLocator.comparableTitle("plain") == "plain")
    }
}

@Suite("the whirlpool motion")
struct WhirlpoolMotionTests {
    @Test func itStartsWhereThePetIsAndEndsInTheTileSmallAndGone() {
        var motion = WhirlpoolMotion(from: CGPoint(x: 400, y: 300), toward: CGPoint(x: 1500, y: 40))
        #expect(motion.center == CGPoint(x: 400, y: 300))
        #expect(motion.scale == 1)
        #expect(motion.opacity == 1)
        var previousScale = motion.scale
        while !motion.isFinished {
            motion.advance(elapsedSeconds: 1.0 / 30.0)
            #expect(motion.scale <= previousScale)
            previousScale = motion.scale
        }
        #expect(abs(motion.center.x - 1500) < 0.001)
        #expect(abs(motion.center.y - 40) < 0.001)
        #expect(motion.scale <= WhirlpoolMotion.smallestScale)
        #expect(motion.opacity == 0)
        #expect(abs(motion.rotationInRadians) > Double.pi * 2)
    }

    @Test func itEasesIn() {
        var motion = WhirlpoolMotion(from: CGPoint(x: 400, y: 300), toward: CGPoint(x: 1500, y: 40))
        motion.advance(elapsedSeconds: WhirlpoolMotion.durationInSeconds / 2)
        #expect(motion.easedProgress < 0.5)
    }

    @Test func aTileFoundLateIsFollowedWithoutAJump() {
        var motion = WhirlpoolMotion(from: CGPoint(x: 400, y: 300), toward: CGPoint(x: 1600, y: 40))
        motion.advance(elapsedSeconds: 0.2)
        var unchanged = motion
        motion.retarget(CGPoint(x: 1400, y: 40))
        motion.advance(elapsedSeconds: 1.0 / 30.0)
        unchanged.advance(elapsedSeconds: 1.0 / 30.0)
        #expect(hypot(motion.center.x - unchanged.center.x, motion.center.y - unchanged.center.y) < 40)
        while !motion.isFinished { motion.advance(elapsedSeconds: 1.0 / 30.0) }
        #expect(motion.center == CGPoint(x: 1400, y: 40))
    }
}
