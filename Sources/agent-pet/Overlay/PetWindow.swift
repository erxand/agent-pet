import AgentPetCore
import AppKit

struct PetWindowSettings: Equatable {
    let styleMask: NSWindow.StyleMask
    let canBecomeKey: Bool
    let canBecomeMain: Bool
    let isMovable: Bool

    static let pet = PetWindowSettings(styleMask: [.borderless], canBecomeKey: false, canBecomeMain: false, isMovable: false)
}

final class PetWindow: NSWindow {
    static let settings = PetWindowSettings.pet

    init(contentRect: CGRect, petContentView: NSView) {
        super.init(contentRect: contentRect, styleMask: PetWindow.settings.styleMask, backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        isMovable = PetWindow.settings.isMovable
        isReleasedWhenClosed = false
        contentView = petContentView
    }

    override var canBecomeKey: Bool { PetWindow.settings.canBecomeKey }

    override var canBecomeMain: Bool { PetWindow.settings.canBecomeMain }
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
