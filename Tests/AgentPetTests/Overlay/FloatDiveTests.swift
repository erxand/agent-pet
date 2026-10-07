import AppKit
import Foundation
import Testing
@testable import AgentPetCore
@testable import agent_pet

@Suite("a pet that dives in a float comes back where it went under")
@MainActor
struct FloatDiveTests {
    @Test func divingMidFloatLeavesThePetStandingWhereItFloated() {
        let view = PetView(
            sessionId: "pet-float",
            petAppearance: PetAppearance(
                label: "float", accent: .cyan, mood: .ready, message: nil, bubbleCaption: nil,
                labelPlacement: .pill, spriteSideLength: 64
            )
        )
        let window = PetWindow(contentRect: CGRect(origin: .zero, size: view.preferredSize), petContentView: view)
        let presence = PetPresence(
            sessionId: "pet-float", window: window, view: view,
            spritePackName: "claude", spriteSheet: SpriteSheet.claude8Bit
        )
        presence.homeHorizontalCenter = 300
        presence.spaceMotion = SpaceMotion(launchingFrom: CGPoint(x: 900, y: 500), seed: 1)
        PetSpaceFlight.leave(presence)
        #expect(presence.spaceMotion == nil)
        #expect(presence.animator.horizontalOffsetFromHome == 600)
        #expect(presence.animator.isWalkingHome)
        window.close()
    }
}
