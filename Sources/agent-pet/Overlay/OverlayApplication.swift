import AgentPetCore
import AppKit

final class OverlayApplicationDelegate: NSObject, NSApplicationDelegate {
    let controller = PetOverlayController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }
}

enum OverlayApplication {
    private static var retainedDelegate: OverlayApplicationDelegate?
    private static var signalSources: [DispatchSourceSignal] = []
    private static let stopSignals: [Int32] = [SIGTERM, SIGINT]
    private static let hardExitDelayInSeconds: TimeInterval = 3
    private static let signalQueue = DispatchQueue(label: "agent-pet.stop-signals")
    private static var stopRequested = false

    static func run() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = OverlayApplicationDelegate()
        retainedDelegate = delegate
        application.delegate = delegate
        if ConfigurationFile.load().divesOnExit {
            diveBeforeExiting(on: stopSignals, controller: delegate.controller)
        }
        application.run()
    }

    private static func diveBeforeExiting(on signals: [Int32], controller: PetOverlayController) {
        signalSources = signals.map { signalNumber in
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: signalQueue)
            source.setEventHandler { [weak controller] in
                guard !stopRequested else { exit(0) }
                stopRequested = true
                signalQueue.asyncAfter(deadline: .now() + hardExitDelayInSeconds) { exit(0) }
                DispatchQueue.main.async {
                    guard let controller else { exit(0) }
                    controller.beginShutdown { exit(0) }
                }
            }
            source.resume()
            return source
        }
    }
}
