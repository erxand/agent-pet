import CoreGraphics
import Foundation
import Testing
@testable import AgentPetCore
@testable import agent_pet

@Suite("the gap between a pet's feet and what it stands on")
@MainActor
struct GroundGapTests {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let side: CGFloat = 64

    @Test func theKeyIsOptionalAndOnlyTakesASaneNumberOfPoints() {
        #expect(ConfigurationFile.parse(Data("{}".utf8)).groundGap == nil)
        #expect(ConfigurationFile.parse(Data(#"{"groundGap": 0}"#.utf8)).groundGap == 0)
        #expect(ConfigurationFile.parse(Data(#"{"groundGap": 2.5}"#.utf8)).groundGap == 2.5)
        #expect(ConfigurationFile.parse(Data(#"{"groundGap": -1}"#.utf8)).groundGap == nil)
        #expect(ConfigurationFile.parse(Data(#"{"groundGap": 500}"#.utf8)).groundGap == nil)
        #expect(ConfigurationFile.parse(Data(#"{"groundGap": "none"}"#.utf8)).groundGap == nil)
    }

    @Test func theCapabilityIsListed() {
        #expect(AgentPetCapability.allCases.map { capability in capability.rawValue }.contains("ground-gap"))
    }

    @Test func withoutTheKeyTheFeetSitWhereTheyAlwaysHave() {
        let pill = LabelLayout(placement: .pill)
        let nametag = LabelLayout(placement: .nametag)
        #expect(PetGeometry.spriteBaseline(layout: pill) == PetGeometry.labelPillHeight + PetGeometry.verticalGap)
        #expect(PetGeometry.spriteBaseline(layout: nametag) == PetGeometry.verticalGap)
        #expect(PetGeometry.totalHeight(spriteSideLength: side, layout: pill) == PetGeometry.totalHeight(spriteSideLength: side, labelPlacement: .pill))
        #expect(pill.labelUnderFeet)
        #expect(!nametag.labelUnderFeet)
    }

    @Test func flushFeetMoveAPillOverTheHeadSoNothingIsDrawnBelowThem() {
        let flushPill = LabelLayout(placement: .pill, feetFlush: true)
        let flushNametag = LabelLayout(placement: .nametag, feetFlush: true)
        for layout in [flushPill, flushNametag] {
            #expect(PetGeometry.spriteBaseline(layout: layout) == 0)
            #expect(!layout.labelUnderFeet)
            #expect(PetGeometry.labelOverHeadBaseline(spriteSideLength: side, layout: layout) == side + PetGeometry.verticalGap)
            #expect(PetGeometry.bubbleBaseline(spriteSideLength: side, layout: layout) > PetGeometry.labelOverHeadBaseline(spriteSideLength: side, layout: layout))
        }
        #expect(
            PetGeometry.bubbleBaseline(spriteSideLength: side, layout: flushPill)
                == side + PetGeometry.verticalGap + PetGeometry.labelPillHeight + PetGeometry.verticalGap
        )
    }

    private func makePresence(feetFlush: Bool) -> PetPresence {
        let view = PetView(
            sessionId: "pet-gap",
            petAppearance: PetAppearance(
                label: "gap", accent: .cyan, mood: .ready, message: nil, bubbleCaption: nil,
                labelPlacement: .nametag, spriteSideLength: side, feetFlush: feetFlush
            )
        )
        let window = PetWindow(contentRect: CGRect(origin: .zero, size: view.preferredSize), petContentView: view)
        return PetPresence(sessionId: "pet-gap", window: window, view: view, spritePackName: "claude", spriteSheet: SpriteSheet.claude8Bit)
    }

    @Test func theGapIsTheSameOnTheScreenBottomAndOnTheDockTop() {
        let sensing = FakeDockSensing()
        sensing.listFrame = CGRect(x: 300, y: 1033, width: 600, height: 74)
        let ground = PetGround { DockGround(sensing: sensing, screenFrames: { [screenFrame] }) }
        let frames = OverlayScreenFrames(visibleFrame: screenFrame, screenFrame: screenFrame)
        let drawnTop: CGFloat = 79
        for gap in [CGFloat(0), 6] {
            ground.refresh(standsOnDock: true, screenFrames: frames, now: 0, elapsedSeconds: 1.0 / 30.0, bottomInset: gap)
            for (center, surface) in [(CGFloat(100), screenFrame.minY), (CGFloat(600), drawnTop)] {
                let presence = makePresence(feetFlush: true)
                let windowBottom = ground.windowBottom(for: presence, standingCenter: center, elapsedSeconds: 1.0 / 30.0)
                let feet = windowBottom + PetGeometry.spriteBaseline(layout: presence.view.petAppearance.labelLayout)
                #expect(feet == surface + gap, "gap \(gap) at \(center)")
                presence.window.close()
            }
        }
    }

    @Test func theDefaultGapIsTodaysOnBothSurfaces() {
        let sensing = FakeDockSensing()
        sensing.listFrame = CGRect(x: 300, y: 1033, width: 600, height: 74)
        let ground = PetGround { DockGround(sensing: sensing, screenFrames: { [screenFrame] }) }
        ground.refresh(
            standsOnDock: true,
            screenFrames: OverlayScreenFrames(visibleFrame: screenFrame, screenFrame: screenFrame),
            now: 0,
            elapsedSeconds: 1.0 / 30.0
        )
        let presence = makePresence(feetFlush: false)
        #expect(ground.windowBottom(for: presence, standingCenter: 100, elapsedSeconds: 1.0 / 30.0) == PetGeometry.windowBottomInset)
        presence.groundBody = nil
        #expect(ground.windowBottom(for: presence, standingCenter: 600, elapsedSeconds: 1.0 / 30.0) == 79 + PetGeometry.windowBottomInset)
        presence.window.close()
    }
}
