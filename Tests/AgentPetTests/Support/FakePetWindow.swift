import AppKit
@testable import agent_pet

final class FakePetWindow: PetWindowing {
    private(set) var frame: NSRect
    var level: NSWindow.Level = .normal
    var ignoresMouseEvents = false
    private(set) var isClosed = false

    init(frame: NSRect) {
        self.frame = frame
    }

    func setFrame(_ frameRect: NSRect, display flag: Bool) {
        frame = frameRect
    }

    func orderOut(_ sender: Any?) {}

    func close() {
        isClosed = true
    }
}
