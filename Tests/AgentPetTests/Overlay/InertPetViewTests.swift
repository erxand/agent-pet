import AppKit
import Foundation
import Testing
import AgentPetCore
@testable import agent_pet

@Suite("an inert pet view takes no input")
@MainActor
struct InertPetViewTests {
    private final class RecordingHandler: PetViewInteractionHandler {
        var clicks: [String] = []

        func petViewDidReceiveLeftClick(sessionId: String) { clicks.append("left \(sessionId)") }
        func petViewDidReceiveRightClick(sessionId: String) { clicks.append("right \(sessionId)") }
    }

    private func makeView() -> PetView {
        let view = PetView(
            sessionId: "pet-inert",
            petAppearance: PetAppearance(
                label: "inert",
                accent: .cyan,
                mood: .needsInput,
                message: "Run the migration?",
                bubbleCaption: nil,
                labelPlacement: .pill,
                spriteSideLength: 64
            )
        )
        view.update(
            spriteImage: NSImage(size: CGSize(width: 64, height: 64)),
            bubbleVerticalOffset: 0,
            groundOffsetFraction: 0,
            chromeOpacity: 1
        )
        return view
    }

    private func click(_ type: NSEvent.EventType) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }

    @Test func inertDropsHitsClicksFirstMouseAndTheTooltipAndAwakeRestoresThem() throws {
        let view = makeView()
        let handler = RecordingHandler()
        view.interactionHandler = handler
        let insideSprite = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        #expect(view.hitTest(insideSprite) === view)
        #expect(view.toolTip == "Run the migration?")

        view.isInert = true
        #expect(view.hitTest(insideSprite) == nil)
        #expect(view.toolTip == nil)
        #expect(!view.acceptsFirstMouse(for: nil))
        view.mouseDown(with: try click(.leftMouseDown))
        view.rightMouseDown(with: try click(.rightMouseDown))
        #expect(handler.clicks.isEmpty)

        view.isInert = false
        #expect(view.hitTest(insideSprite) === view)
        #expect(view.toolTip == "Run the migration?")
        #expect(view.acceptsFirstMouse(for: nil))
        view.mouseDown(with: try click(.leftMouseDown))
        #expect(handler.clicks == ["left pet-inert"])
    }

    @Test func aPetWindowNeverBecomesKeyOrMain() {
        let window = PetWindow(contentRect: CGRect(x: 0, y: 0, width: 10, height: 10), petContentView: NSView())
        #expect(!window.canBecomeKey)
        #expect(!window.canBecomeMain)
        #expect(window.styleMask == [.borderless])
        #expect(!window.isMovable)
        #expect(!window.isVisible)
    }
}
