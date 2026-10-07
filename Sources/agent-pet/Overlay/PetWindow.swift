import AgentPetCore
import AppKit

final class PetWindow: NSWindow {
    static let style: NSWindow.StyleMask = [.borderless]
    static let takesKeyOrMain = false
    static let movable = false

    init(contentRect: CGRect, petContentView: NSView) {
        super.init(contentRect: contentRect, styleMask: PetWindow.style, backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        isMovable = PetWindow.movable
        isReleasedWhenClosed = false
        contentView = petContentView
    }

    override var canBecomeKey: Bool { PetWindow.takesKeyOrMain }

    override var canBecomeMain: Bool { PetWindow.takesKeyOrMain }
}

protocol PetWindowing: AnyObject {
    var frame: NSRect { get }
    var level: NSWindow.Level { get set }
    var ignoresMouseEvents: Bool { get set }
    func setFrame(_ frameRect: NSRect, display flag: Bool)
    func orderOut(_ sender: Any?)
    func close()
}

extension PetWindow: PetWindowing {}
