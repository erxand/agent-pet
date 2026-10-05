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
    // The last word on a stop: the process exits this long after the signal even when the main
    // thread is stuck and the controller's own deadline never runs.
    private static let hardExitDelayInSeconds: TimeInterval = 3
    private static let signalQueue = DispatchQueue(label: "agent-pet.stop-signals")
    // Read and written only on `signalQueue`.
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

    // launchd stops the daemon with SIGTERM (kickstart -k onto a new build,
    // bootout); Ctrl-C on `agent-pet daemon` is SIGINT. With `diveOnExit` in
    // the config, either one dives the pets on screen before the process
    // exits, instead of dropping them. The dive takes under half a second,
    // far inside launchd's exit timeout. Without it the signals keep their
    // default action, as upstream.
    private static func diveBeforeExiting(on signals: [Int32], controller: PetOverlayController) {
        signalSources = signals.map { signalNumber in
            signal(signalNumber, SIG_IGN)
            // Off the main thread, so a stuck main thread still exits on time.
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: signalQueue)
            source.setEventHandler { [weak controller] in
                // A second signal while the pets dive means "now".
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
