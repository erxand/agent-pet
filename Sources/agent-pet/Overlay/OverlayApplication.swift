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

    static func run() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = OverlayApplicationDelegate()
        retainedDelegate = delegate
        application.delegate = delegate
        diveBeforeExiting(on: stopSignals, controller: delegate.controller)
        application.run()
    }

    // launchd stops the daemon with SIGTERM (kickstart -k onto a new build,
    // bootout); Ctrl-C on `agent-pet daemon` is SIGINT. Either one dives the
    // pets on screen before the process exits, instead of dropping them.
    // The dive takes under half a second, far inside launchd's exit timeout.
    private static func diveBeforeExiting(on signals: [Int32], controller: PetOverlayController) {
        signalSources = signals.map { signalNumber in
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak controller] in
                // A second signal while the pets dive means "now".
                guard let controller, !controller.isShuttingDown else { exit(0) }
                controller.beginShutdown { exit(0) }
            }
            source.resume()
            return source
        }
    }
}
