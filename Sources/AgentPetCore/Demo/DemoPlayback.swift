import Foundation

package final class DemoPlayback {
    package static let interruptedExitCodeBase: Int32 = 128
    package static let idleWaitInSeconds: TimeInterval = 0.05

    private static let tickIntervalInSeconds: TimeInterval = 1.0 / 30.0
    private static let maximumTickInSeconds: TimeInterval = 0.25
    private static let settleTimeoutInSeconds: TimeInterval = 2.5
    private static let stoppingSignals: [Int32] = [SIGINT, SIGTERM]

    package let runner: DemoRunner
    private let stage: DemoStage
    private let speed: Double
    private let reportStop: (String) -> Void
    private let onFinish: (Int32) -> Void
    private let focus: DemoFocus?

    private var timer: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private var lastTickDate = Date()
    private var settlingSeconds: TimeInterval = 0
    private var hasFinished = false

    package init(
        runner: DemoRunner,
        stage: DemoStage,
        speed: Double,
        reportStop: @escaping (String) -> Void,
        focus: DemoFocus? = nil,
        onFinish: @escaping (Int32) -> Void
    ) {
        self.runner = runner
        self.stage = stage
        self.speed = speed
        self.reportStop = reportStop
        self.focus = focus
        self.onFinish = onFinish
    }

    package func start() {
        installSignalSources()
        focus?.takeFocus()
        lastTickDate = Date()
        runner.start()
        let timer = Timer(timeInterval: DemoPlayback.tickIntervalInSeconds, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    package func interrupt(signal signalNumber: Int32) {
        guard !hasFinished else { return }
        runner.stop()
        reportStop("demo stopped by \(DemoPlayback.signalName(signalNumber)). All demo windows are closed.")
        complete(exitCode: DemoPlayback.interruptedExitCodeBase + signalNumber)
    }

    package func handle(key: DemoKey) -> Bool {
        guard !hasFinished else { return false }
        switch key {
        case .space:
            runner.skipToNextScene()
        case .escape:
            runner.stop()
            reportStop("demo stopped by esc. All demo windows are closed.")
            complete(exitCode: ExitCode.success)
        }
        return true
    }

    private func tick() {
        let now = Date()
        let elapsedSeconds = min(now.timeIntervalSince(lastTickDate), DemoPlayback.maximumTickInSeconds)
        lastTickDate = now
        runner.advance(byElapsedSeconds: elapsedSeconds * speed)
        stage.advance(elapsedSeconds: elapsedSeconds, sceneProgress: runner.sceneProgress)
        guard runner.isFinished else { return }
        settlingSeconds += elapsedSeconds
        guard stage.isSettled || settlingSeconds >= DemoPlayback.settleTimeoutInSeconds else { return }
        runner.stop()
        complete(exitCode: ExitCode.success)
    }

    private func complete(exitCode: Int32) {
        guard !hasFinished else { return }
        hasFinished = true
        timer?.invalidate()
        timer = nil
        for source in signalSources {
            source.cancel()
        }
        signalSources = []
        focus?.returnFocus()
        onFinish(exitCode)
    }

    private func installSignalSources() {
        for signalNumber in DemoPlayback.stoppingSignals {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                self?.interrupt(signal: signalNumber)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private static func signalName(_ signalNumber: Int32) -> String {
        switch signalNumber {
        case SIGINT: return "ctrl-c"
        case SIGTERM: return "SIGTERM"
        default: return "signal \(signalNumber)"
        }
    }
}
