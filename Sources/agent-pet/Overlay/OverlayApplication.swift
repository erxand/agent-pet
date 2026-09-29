import AppKit

final class OverlayApplicationDelegate: NSObject, NSApplicationDelegate {
    private let controller = PetOverlayController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }
}

enum OverlayApplication {
    private static var retainedDelegate: OverlayApplicationDelegate?

    static func run() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = OverlayApplicationDelegate()
        retainedDelegate = delegate
        application.delegate = delegate
        application.run()
    }
}
