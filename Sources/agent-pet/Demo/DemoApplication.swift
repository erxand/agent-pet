import AgentPetCore
import AppKit

final class DemoKeyWindow: NSWindow {
    private static let sideLength: CGFloat = 1

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: DemoKeyWindow.sideLength, height: DemoKeyWindow.sideLength),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { false }
}

final class DemoAppFocus: DemoFocus {
    private let keyWindow = DemoKeyWindow()
    private var previousApplication: NSRunningApplication?

    func takeFocus() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApplication = frontmost == NSRunningApplication.current ? nil : frontmost
        keyWindow.orderFrontRegardless()
        NSApplication.shared.activate()
        keyWindow.makeKey()
    }

    func returnFocus() {
        if NSApplication.shared.isActive, let previousApplication, !previousApplication.isTerminated {
            previousApplication.activate(from: NSRunningApplication.current, options: [])
        }
        keyWindow.orderOut(nil)
        keyWindow.close()
    }
}

final class DemoApplicationDelegate: NSObject, NSApplicationDelegate {
    private static let successExitCode: Int32 = 0
    private static let ignoredModifiers: NSEvent.ModifierFlags = [.command, .control, .option]

    private let request: DemoRequest
    private var playback: DemoPlayback?
    private var keyMonitor: Any?
    private(set) var exitCode: Int32 = DemoApplicationDelegate.successExitCode

    init(request: DemoRequest) {
        self.request = request
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let stage = DemoOverlayStage()
        let runner = DemoRunner(scenes: request.scenes, stage: stage, waitsForUser: request.waitsForUser)
        let playback = DemoPlayback(
            runner: runner,
            stage: stage,
            speed: request.speed,
            reportStop: { line in print(line) },
            focus: DemoAppFocus(),
            onFinish: { [weak self] finishedExitCode in
                self?.exitCode = finishedExitCode
                self?.removeKeyMonitor()
                DemoApplication.stopRunLoop()
            }
        )
        self.playback = playback
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(DemoApplicationDelegate.ignoredModifiers).isEmpty,
                  let key = DemoKey(keyCode: event.keyCode),
                  let playback = self?.playback,
                  playback.handle(key: key) else { return event }
            return nil
        }
        playback.start()
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
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
        if request.waitsForUser {
            print("agent-pet demo: press space for the next scene. Press esc to quit.")
        } else {
            let seconds = DemoSnapshot.formattedSeconds(request.scenes.reduce(0) { total, scene in total + scene.durationInSeconds } / request.speed)
            print("agent-pet demo: \(seconds) s. Press esc to quit.")
        }
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
