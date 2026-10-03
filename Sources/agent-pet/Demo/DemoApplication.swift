import AgentPetCore
import AppKit

final class DemoApplicationDelegate: NSObject, NSApplicationDelegate {
    private static let successExitCode: Int32 = 0

    private let request: DemoRequest
    private var playback: DemoPlayback?
    private(set) var exitCode: Int32 = DemoApplicationDelegate.successExitCode

    init(request: DemoRequest) {
        self.request = request
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let stage = DemoOverlayStage()
        let runner = DemoRunner(scenes: request.scenes, stage: stage)
        stage.onPetClicked = { [weak runner] petKey in runner?.handleClick(petKey: petKey) }
        stage.onCaptionClicked = { [weak runner] in runner?.skipToNextScene() }
        let playback = DemoPlayback(
            runner: runner,
            stage: stage,
            speed: request.speed,
            reportStop: { line in print(line) },
            onFinish: { [weak self] finishedExitCode in
                self?.exitCode = finishedExitCode
                DemoApplication.stopRunLoop()
            }
        )
        self.playback = playback
        playback.start()
    }
}

enum DemoApplication {
    private static var retainedDelegate: DemoApplicationDelegate?

    static func run(_ request: DemoRequest) -> Int32 {
        switch request.mode {
        case .play:
            return play(request)
        case .snapshot(let directory):
            return DemoSnapshot.write(scenes: request.scenes, to: directory)
        }
    }

    private static func play(_ request: DemoRequest) -> Int32 {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = DemoApplicationDelegate(request: request)
        retainedDelegate = delegate
        application.delegate = delegate
        print("agent-pet demo: \(DemoSnapshot.formattedSeconds(request.scenes.reduce(0) { total, scene in total + scene.durationInSeconds } / request.speed)) s. "
            + "Click the caption to skip a scene, ctrl-c to quit.")
        application.run()
        return delegate.exitCode
    }

    static func stopRunLoop() {
        let application = NSApplication.shared
        application.stop(nil)
        guard let wakeEvent = NSEvent.otherEvent(
            with: .applicationDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 0,
            data1: 0,
            data2: 0
        ) else { return }
        application.postEvent(wakeEvent, atStart: false)
    }
}
