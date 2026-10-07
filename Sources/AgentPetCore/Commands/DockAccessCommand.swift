import ApplicationServices
import Foundation

package protocol DockAccessChecking {
    func isGranted() -> Bool
    func ask() -> Bool
}

package struct AccessibilityDockAccess: DockAccessChecking {
    package init() {}

    package func isGranted() -> Bool {
        AXIsProcessTrusted()
    }

    package func ask() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

package struct DockAccessReport: Codable, Equatable {
    package let granted: Bool
    package let processIdentifier: Int32
    package let checkedAt: TimeInterval
    package let askedAt: TimeInterval?

    package init(granted: Bool, processIdentifier: Int32, checkedAt: TimeInterval, askedAt: TimeInterval?) {
        self.granted = granted
        self.processIdentifier = processIdentifier
        self.checkedAt = checkedAt
        self.askedAt = askedAt
    }
}

package struct DockAccessFiles {
    private static let reportFileName = "dock-access.json"
    private static let requestFileName = "dock-access-ask"

    package let reportFile: URL
    package let requestFile: URL

    package init(reportFile: URL, requestFile: URL) {
        self.reportFile = reportFile
        self.requestFile = requestFile
    }

    package static var standard: DockAccessFiles {
        DockAccessFiles(
            reportFile: PetPaths.stateDirectory.appendingPathComponent(reportFileName, isDirectory: false),
            requestFile: PetStateFile.controlDirectory.appendingPathComponent(requestFileName, isDirectory: false)
        )
    }

    package func loadReport() -> DockAccessReport? {
        guard let payload = try? Data(contentsOf: reportFile) else { return nil }
        return try? JSONDecoder().decode(DockAccessReport.self, from: payload)
    }

    package func save(_ report: DockAccessReport) {
        guard let payload = try? JSONEncoder().encode(report) else { return }
        PetStateFile.writeAtomically(payload, to: reportFile)
    }

    @discardableResult
    package func writeRequest() -> Bool {
        PetStateFile.writeAtomically(Data(), to: requestFile)
    }

    package func consumeRequest() -> Bool {
        guard FileManager.default.fileExists(atPath: requestFile.path) else { return false }
        try? FileManager.default.removeItem(at: requestFile)
        return true
    }
}

package final class DockAccessReporter {
    package static let checkIntervalInSeconds: TimeInterval = 5

    private let files: DockAccessFiles
    private let access: DockAccessChecking
    private let processIdentifier: Int32
    private var lastCheckAt: TimeInterval?
    private var lastWritten: Bool?

    package private(set) var isGranted = false

    package init(files: DockAccessFiles, access: DockAccessChecking, processIdentifier: Int32) {
        self.files = files
        self.access = access
        self.processIdentifier = processIdentifier
    }

    package func tick(now: TimeInterval) {
        if files.consumeRequest() {
            isGranted = access.ask()
            lastCheckAt = now
            write(now: now, askedAt: now)
            return
        }
        if let lastCheckAt, now - lastCheckAt < DockAccessReporter.checkIntervalInSeconds { return }
        lastCheckAt = now
        isGranted = access.isGranted()
        guard lastWritten != isGranted else { return }
        write(now: now, askedAt: nil)
    }

    private func write(now: TimeInterval, askedAt: TimeInterval?) {
        files.save(DockAccessReport(granted: isGranted, processIdentifier: processIdentifier, checkedAt: now, askedAt: askedAt))
        lastWritten = isGranted
    }
}

enum DockAccessCommand {
    static let grantedWord = "granted"
    static let notGrantedWord = "not granted"
    static let unknownWord = "unknown"
    static let settingsHint = "System Settings > Privacy & Security > Accessibility"
    static let answerWaitInSeconds: TimeInterval = 3
    static let answerPollInSeconds: TimeInterval = 0.1

    struct Environment {
        var files: DockAccessFiles
        var liveDaemonProcessIdentifier: () -> Int32?
        var ensureDaemon: () -> Void
        var now: () -> TimeInterval
        var sleep: (TimeInterval) -> Void

        static var live: Environment {
            Environment(
                files: .standard,
                liveDaemonProcessIdentifier: {
                    guard let recorded = DaemonProcessIdentifierFile.read(),
                          ProcessLiveness.isAlive(processIdentifier: recorded) else { return nil }
                    return recorded
                },
                ensureDaemon: DaemonCommand.ensureRunning,
                now: { Date().timeIntervalSince1970 },
                sleep: { seconds in Thread.sleep(forTimeInterval: seconds) }
            )
        }
    }

    static func run(flags: ParsedFlags, environment: Environment = .live) -> Int32 {
        flags.isPresent(.ask) ? ask(environment: environment) : check(environment: environment)
    }

    private static func check(environment: Environment) -> Int32 {
        guard let daemon = environment.liveDaemonProcessIdentifier(),
              let report = environment.files.loadReport(),
              report.processIdentifier == daemon
        else {
            print(unknownWord)
            CommandFeedback.writeToStandardError("the daemon is not running or has not checked yet; the daemon's own access is what counts.")
            return ExitCode.failure
        }
        return answer(report.granted, asked: false)
    }

    private static func ask(environment: Environment) -> Int32 {
        environment.ensureDaemon()
        let requestedAt = environment.now()
        guard environment.files.writeRequest() else {
            CommandFeedback.writeToStandardError("cannot write \(environment.files.requestFile.path).")
            return ExitCode.failure
        }
        let deadline = requestedAt + answerWaitInSeconds
        while environment.now() < deadline {
            if let daemon = environment.liveDaemonProcessIdentifier(),
               let report = environment.files.loadReport(),
               report.processIdentifier == daemon,
               let askedAt = report.askedAt, askedAt > requestedAt {
                return answer(report.granted, asked: true)
            }
            environment.sleep(answerPollInSeconds)
        }
        print(unknownWord)
        CommandFeedback.writeToStandardError("the daemon did not answer; it asks macOS the next time it starts.")
        return ExitCode.failure
    }

    private static func answer(_ granted: Bool, asked: Bool) -> Int32 {
        print(granted ? grantedWord : notGrantedWord)
        guard !granted else { return ExitCode.success }
        if asked {
            CommandFeedback.writeToStandardError("turn on agent-pet in \(settingsHint); the daemon notices within 5 seconds.")
        }
        return ExitCode.failure
    }
}
