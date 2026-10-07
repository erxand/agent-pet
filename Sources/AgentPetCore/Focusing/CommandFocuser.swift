import Foundation

package struct CommandFocuser: Focuser {
    private enum TimeoutOutcome: String {
        case terminated
        case killed
    }

    package static let defaultTimeoutInSeconds: TimeInterval = 5

    private static let pollIntervalInSeconds: TimeInterval = 0.02
    package static let defaultTerminationGraceInSeconds: TimeInterval = 1
    private static let secondsFormat = "%g"
    private static let missingValue = ""

    private let arguments: [String]
    private let timeoutInSeconds: TimeInterval
    private let terminationGraceInSeconds: TimeInterval
    private let waitsForCompletion: Bool
    private let report: (String) -> Void
    private let runningCommands: RunningFocusCommands

    package init(
        arguments: [String],
        timeoutInSeconds: TimeInterval = CommandFocuser.defaultTimeoutInSeconds,
        terminationGraceInSeconds: TimeInterval = CommandFocuser.defaultTerminationGraceInSeconds,
        waitsForCompletion: Bool,
        report: @escaping (String) -> Void = CommandFeedback.writeToStandardError,
        runningCommands: RunningFocusCommands = .shared
    ) {
        self.runningCommands = runningCommands
        self.arguments = arguments
        self.timeoutInSeconds = timeoutInSeconds
        self.terminationGraceInSeconds = terminationGraceInSeconds
        self.waitsForCompletion = waitsForCompletion
        self.report = report
    }

    package func unavailability(for request: FocusRequest) -> FocusUnavailability? {
        nil
    }

    package static func environment(for request: FocusRequest, inheriting inherited: [String: String]) -> [String: String] {
        var environment = inherited
        environment[EnvironmentVariableName.focusSessionId] = request.sessionId
        environment[EnvironmentVariableName.focusProcessIdentifier] = request.processIdentifier.map { processIdentifier in
            String(processIdentifier)
        } ?? missingValue
        environment[EnvironmentVariableName.focusTarget] = request.focusTarget ?? missingValue
        environment[EnvironmentVariableName.focusGroup] = request.group
        environment[EnvironmentVariableName.focusAgent] = request.agent.rawValue
        return environment
    }

    package func focus(_ request: FocusRequest) {
        guard let executablePath = arguments.first else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = Array(arguments.dropFirst())
        process.environment = CommandFocuser.environment(for: request, inheriting: ProcessInfo.processInfo.environment)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            report("focus command \(executablePath) could not start: \(error.localizedDescription)")
            return
        }
        runningCommands.add(process)
        let timeoutInSeconds = timeoutInSeconds
        let terminationGraceInSeconds = terminationGraceInSeconds
        let report = report
        let runningCommands = runningCommands
        let supervise = {
            CommandFocuser.supervise(
                process,
                runningCommands: runningCommands,
                executablePath: executablePath,
                timeoutInSeconds: timeoutInSeconds,
                terminationGraceInSeconds: terminationGraceInSeconds,
                report: report
            )
        }
        if waitsForCompletion {
            supervise()
        } else {
            Thread.detachNewThread(supervise)
        }
    }

    private static func supervise(
        _ process: Process,
        runningCommands: RunningFocusCommands,
        executablePath: String,
        timeoutInSeconds: TimeInterval,
        terminationGraceInSeconds: TimeInterval,
        report: (String) -> Void
    ) {
        waitForExit(of: process, upTo: timeoutInSeconds)
        defer { runningCommands.remove(process) }
        guard !runningCommands.wasCancelled(process) else { return }
        if process.isRunning {
            process.terminate()
            waitForExit(of: process, upTo: terminationGraceInSeconds)
            let outcome: TimeoutOutcome
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                outcome = .killed
            } else {
                outcome = .terminated
            }
            report("focus command \(executablePath) timed out after \(formattedSeconds(timeoutInSeconds)) s and was \(outcome.rawValue)")
            return
        }
        guard process.terminationStatus != ExitCode.success else { return }
        report("focus command \(executablePath) exited \(process.terminationStatus)")
    }

    private static func waitForExit(of process: Process, upTo seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: pollIntervalInSeconds)
        }
    }

    private static func formattedSeconds(_ seconds: TimeInterval) -> String {
        String(format: secondsFormat, seconds)
    }
}

package final class RunningFocusCommands {
    package static let shared = RunningFocusCommands()

    package init() {}

    private let lock = NSLock()
    private var runningByProcessIdentifier: [Int32: Process] = [:]
    private var cancelledProcessIdentifiers: Set<Int32> = []

    package var runningCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return runningByProcessIdentifier.count
    }

    func add(_ process: Process) {
        lock.lock()
        runningByProcessIdentifier[process.processIdentifier] = process
        lock.unlock()
    }

    func remove(_ process: Process) {
        lock.lock()
        runningByProcessIdentifier.removeValue(forKey: process.processIdentifier)
        cancelledProcessIdentifiers.remove(process.processIdentifier)
        lock.unlock()
    }

    func wasCancelled(_ process: Process) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelledProcessIdentifiers.contains(process.processIdentifier)
    }

    @discardableResult
    package func cancelAll() -> Int {
        lock.lock()
        let running = Array(runningByProcessIdentifier.values)
        for process in running {
            cancelledProcessIdentifiers.insert(process.processIdentifier)
        }
        lock.unlock()
        for process in running where process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        return running.count
    }
}
