import CoreGraphics
import Foundation
import Testing
import AgentPetCore
@testable import agent_pet

@Suite("labels can stay home while pets float")
struct FloatingLabelTests {
    private let area = SpaceArea(lowestCenter: CGPoint(x: 40, y: 40), highestCenter: CGPoint(x: 1400, y: 860))

    private func floating() -> SpaceMotion {
        SpaceMotion(launchingFrom: CGPoint(x: 400, y: 40), seed: 7)
    }

    @Test func labelsShowWhileFloatingUnlessTheKeyIsOn() {
        let motion = floating()
        #expect(PetChrome.shownOpacity(1, spaceMotion: motion, hidesLabelsWhileFloating: false) == 1)
        #expect(PetChrome.shownOpacity(1, spaceMotion: motion, hidesLabelsWhileFloating: true) == 0)
        #expect(PetChrome.shownOpacity(0.4, spaceMotion: nil, hidesLabelsWhileFloating: true) == 0.4)
    }

    @Test func labelsComeBackOnLanding() {
        var motion = floating()
        motion.returnToGround()
        #expect(PetChrome.shownOpacity(1, spaceMotion: motion, hidesLabelsWhileFloating: true) == 0)
        for _ in 0..<200 where !motion.isOnGround {
            motion.advance(elapsedSeconds: 1.0 / 30.0, area: area, homeCenterX: 400)
        }
        #expect(motion.isOnGround)
        #expect(PetChrome.shownOpacity(1, spaceMotion: motion, hidesLabelsWhileFloating: true) == 1)
    }

    @Test func aPetThatDivesMidFloatWithHiddenLabelsNeverFlashesThem() {
        let animator = PetAnimator()
        for _ in 0..<30 { animator.advance(elapsedSeconds: 1.0 / 30.0, mood: .ready) }
        #expect(animator.chromeOpacity == 1)
        animator.hideChrome()
        animator.requestDive()
        var ticks = 0
        while !animator.isSubmerged && ticks < 100 {
            #expect(animator.chromeOpacity == 0)
            animator.advance(elapsedSeconds: 1.0 / 30.0, mood: .ready)
            ticks += 1
        }
        #expect(animator.isSubmerged)
    }

    @Test func theConfigKeyDefaultsOff() {
        #expect(!ConfigurationFile.parse(Data("{}".utf8)).hidesLabelsWhileFloating)
        #expect(ConfigurationFile.parse(Data(#"{"hideLabelsWhileFloating": true}"#.utf8)).hidesLabelsWhileFloating)
        #expect(!ConfigurationFile.parse(Data(#"{"hideLabelsWhileFloating": "yes"}"#.utf8)).hidesLabelsWhileFloating)
    }
}
