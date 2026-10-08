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
    package let askNonce: String?

    package init(granted: Bool, processIdentifier: Int32, checkedAt: TimeInterval, askedAt: TimeInterval?, askNonce: String? = nil) {
        self.granted = granted
        self.processIdentifier = processIdentifier
        self.checkedAt = checkedAt
        self.askedAt = askedAt
        self.askNonce = askNonce
    }
}

package struct DockAccessFiles {
    private static let reportFileName = "dock-access.json"
    private static let requestFileName = "dock-access-ask"
    private static let claimSuffix = ".claimed-"

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

    package func pendingRequestNonce() -> String? {
        guard let payload = try? Data(contentsOf: requestFile) else { return nil }
        let nonce = String(decoding: payload, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return nonce.isEmpty ? nil : nonce
    }

    @discardableResult
    package func writeRequest(nonce: String) -> Bool {
        PetStateFile.writeAtomically(Data(nonce.utf8), to: requestFile)
    }

    package func removeClaims() {
        let directory = requestFile.deletingLastPathComponent()
        let claimPrefix = ".\(requestFile.lastPathComponent)\(DockAccessFiles.claimSuffix)"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix(claimPrefix) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name, isDirectory: false))
        }
    }

    package func consumeRequest() -> String? {
        let claimed = requestFile.deletingLastPathComponent()
            .appendingPathComponent(".\(requestFile.lastPathComponent)\(DockAccessFiles.claimSuffix)\(UUID().uuidString)", isDirectory: false)
        guard rename(requestFile.path, claimed.path) == 0 else { return nil }
        defer { try? FileManager.default.removeItem(at: claimed) }
        guard let payload = try? Data(contentsOf: claimed) else { return "" }
        return String(decoding: payload, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

package final class DockAccessReporter {
    package static let checkIntervalInSeconds: TimeInterval = 5
    package static let askCooldownInSeconds: TimeInterval = 10

    private let files: DockAccessFiles
    private let access: DockAccessChecking
    private let processIdentifier: Int32
    private let clock: () -> TimeInterval
    private var lastCheckAt: TimeInterval?
    private var lastWritten: Bool?
    private var lastAskAt: TimeInterval?
    private var removedClaims = false

    package private(set) var isGranted = false

    package init(
        files: DockAccessFiles,
        access: DockAccessChecking,
        processIdentifier: Int32,
        clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) {
        self.files = files
        self.access = access
        self.processIdentifier = processIdentifier
        self.clock = clock
    }

    package func tick() {
        let now = clock()
        if !removedClaims {
            removedClaims = true
            files.removeClaims()
        }
        if let nonce = files.consumeRequest() {
            answer(nonce: nonce, now: now)
            return
        }
        if let lastCheckAt, now - lastCheckAt < DockAccessReporter.checkIntervalInSeconds { return }
        lastCheckAt = now
        isGranted = access.isGranted()
        guard lastWritten != isGranted || files.loadReport()?.processIdentifier != processIdentifier else { return }
        write(checkedAt: now, askedAt: nil, nonce: nil)
    }

    private func answer(nonce: String, now: TimeInterval) {
        let recentlyAsked = lastAskAt.map { askedAt in now - askedAt < DockAccessReporter.askCooldownInSeconds } ?? false
        if recentlyAsked {
            isGranted = access.isGranted()
        } else {
            isGranted = access.ask()
            lastAskAt = now
        }
        let answeredAt = clock()
        lastCheckAt = answeredAt
        write(checkedAt: answeredAt, askedAt: answeredAt, nonce: nonce)
    }

    private func write(checkedAt: TimeInterval, askedAt: TimeInterval?, nonce: String?) {
        files.save(DockAccessReport(
            granted: isGranted,
            processIdentifier: processIdentifier,
            checkedAt: checkedAt,
            askedAt: askedAt,
            askNonce: nonce
        ))
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
        var startDaemon: () -> DaemonStart
        var makeNonce: () -> String
        var now: () -> TimeInterval
        var sleep: (TimeInterval) -> Void
        var writeError: (String) -> Void = CommandFeedback.writeToStandardError

        static var live: Environment {
            Environment(
                files: .standard,
                liveDaemonProcessIdentifier: {
                    guard let recorded = DaemonProcessIdentifierFile.read(),
                          ProcessLiveness.isAlive(processIdentifier: recorded) else { return nil }
                    return recorded
                },
                startDaemon: DaemonCommand.ensureRunningOnItsOwn,
                makeNonce: { UUID().uuidString },
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
            environment.writeError("the daemon is not running or has not checked yet; the daemon's own access is what counts.")
            return ExitCode.failure
        }
        return answer(report.granted, asked: false, environment: environment)
    }

    private static func ask(environment: Environment) -> Int32 {
        let start = environment.startDaemon()
        switch start {
        case .refusedForeignHome:
            environment.writeError(AccountHome.refusalMessage())
            return ExitCode.failure
        case .launchAgent, .spawnedOnItsOwn:
            break
        case .alreadyRunningWithoutLaunchAgent, .spawnedByThisCommand:
            environment.writeError(
                "no launch agent runs the daemon, so macOS may show and record this grant for the app that started it."
            )
        }
        let nonce: String
        if let pending = environment.files.pendingRequestNonce() {
            nonce = pending
        } else {
            nonce = environment.makeNonce()
            guard environment.files.writeRequest(nonce: nonce) else {
                environment.writeError("cannot write \(environment.files.requestFile.path).")
                return ExitCode.failure
            }
        }
        let deadline = environment.now() + answerWaitInSeconds
        while environment.now() < deadline {
            if let daemon = environment.liveDaemonProcessIdentifier(),
               let report = environment.files.loadReport(),
               report.processIdentifier == daemon,
               report.askNonce == nonce {
                return answer(report.granted, asked: true, environment: environment)
            }
            environment.sleep(answerPollInSeconds)
        }
        print(unknownWord)
        environment.writeError("the daemon did not answer; it asks macOS the next time it starts.")
        return ExitCode.failure
    }

    private static func answer(_ granted: Bool, asked: Bool, environment: Environment) -> Int32 {
        print(granted ? grantedWord : notGrantedWord)
        guard !granted else { return ExitCode.success }
        if asked {
            environment.writeError("turn on AgentPet in \(settingsHint); the daemon notices within \(Int(DockAccessReporter.checkIntervalInSeconds)) seconds.")
        }
        return ExitCode.failure
    }
}
