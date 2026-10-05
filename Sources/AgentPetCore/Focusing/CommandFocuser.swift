import Foundation

package struct CommandFocuser: Focuser {
    private enum TimeoutOutcome: String {
        case terminated
        case killed
    }

    package static let defaultTimeoutInSeconds: TimeInterval = 5

    private static let pollIntervalInSeconds: TimeInterval = 0.02
    private static let terminationGraceInSeconds: TimeInterval = 1
    private static let secondsFormat = "%g"
    private static let missingValue = ""

    private let arguments: [String]
    private let timeoutInSeconds: TimeInterval
    private let waitsForCompletion: Bool
    private let report: (String) -> Void

    package init(
        arguments: [String],
        timeoutInSeconds: TimeInterval = CommandFocuser.defaultTimeoutInSeconds,
        waitsForCompletion: Bool,
        report: @escaping (String) -> Void = CommandFeedback.writeToStandardError
    ) {
        self.arguments = arguments
        self.timeoutInSeconds = timeoutInSeconds
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
        let timeoutInSeconds = timeoutInSeconds
        let report = report
        let supervise = {
            CommandFocuser.supervise(
                process,
                executablePath: executablePath,
                timeoutInSeconds: timeoutInSeconds,
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
        executablePath: String,
        timeoutInSeconds: TimeInterval,
        report: (String) -> Void
    ) {
        waitForExit(of: process, upTo: timeoutInSeconds)
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
