import AgentPetCore
import AppKit

final class PetWindow: NSWindow {
    init(contentRect: CGRect, petContentView: NSView) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        isMovable = false
        isReleasedWhenClosed = false
        contentView = petContentView
    }

    override var canBecomeKey: Bool { false }

    override var canBecomeMain: Bool { false }
}
