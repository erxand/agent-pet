import Foundation

enum DaemonCommand {
    struct Foreground {
        var prepare: () -> Void
        var otherLiveDaemon: () -> Int32?
        var ownExecutableIsFound: () -> Bool
        var claim: () -> Void
        var writeError: (String) -> Void

        static var live: Foreground {
            Foreground(
                prepare: PetPaths.createStateDirectoriesIfNeeded,
                otherLiveDaemon: {
                    guard let recorded = DaemonProcessIdentifierFile.read(),
                          recorded != ProcessInfo.processInfo.processIdentifier,
                          ProcessLiveness.isAlive(processIdentifier: recorded) else { return nil }
                    return recorded
                },
                ownExecutableIsFound: OwnExecutable.isFoundThroughMainBundle,
                claim: {
                    let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
                    DaemonLogFile.truncateIfOversized()
                    DaemonLogFile.writeStartupLine(
                        processIdentifier: ownProcessIdentifier,
                        parentProcessIdentifier: getppid()
                    )
                    DaemonProcessIdentifierFile.write(processIdentifier: ownProcessIdentifier)
                },
                writeError: CommandFeedback.writeToStandardError
            )
        }
    }

    static let ownExecutableMissingMessage = "the daemon cannot find its own executable through its main bundle,"
        + " so the window server would refuse it; not starting. macOS may have denied it the folder it is in."

    static func runInForeground(runOverlay: () -> Void) -> Int32 {
        runInForeground(using: .live, runOverlay: runOverlay)
    }

    static func runInForeground(using foreground: Foreground, runOverlay: () -> Void) -> Int32 {
        foreground.prepare()
        if foreground.otherLiveDaemon() != nil {
            return ExitCode.success
        }
        guard foreground.ownExecutableIsFound() else {
            foreground.writeError(ownExecutableMissingMessage)
            return ExitCode.failure
        }
        foreground.claim()
        runOverlay()
        return ExitCode.success
    }

    static func ensureRunning() {
        _ = ensureRunningOnItsOwn()
    }

    struct Starter {
        var launchAgentIsInstalled: () -> Bool
        var startLaunchAgent: () -> Void
        var runningDaemon: () -> Int32?
        var parentOf: (Int32) -> Int32?
        var spawnDetached: () -> Bool

        static var live: Starter {
            Starter(
                launchAgentIsInstalled: { LaunchAgent.isInstalled },
                startLaunchAgent: LaunchAgent.start,
                runningDaemon: {
                    guard let recorded = DaemonProcessIdentifierFile.read(),
                          ProcessLiveness.isAlive(processIdentifier: recorded) else { return nil }
                    return recorded
                },
                parentOf: ProcessParent.of,
                spawnDetached: DaemonCommand.spawnDetached
            ).honouringNeverStart(ProcessInfo.processInfo.environment)
        }

        func honouringNeverStart(_ environment: [String: String]) -> Starter {
            guard environment[EnvironmentVariableName.neverStartDaemon] == Starter.neverStartValue else { return self }
            var starter = self
            starter.startLaunchAgent = {}
            starter.spawnDetached = { false }
            return starter
        }

        static let neverStartValue = "1"
    }

    static func ensureRunningOnItsOwn() -> DaemonStart {
        PetPaths.createStateDirectoriesIfNeeded()
        return ensureRunningOnItsOwn(using: .live)
    }

    static func ensureRunningOnItsOwn(using starter: Starter) -> DaemonStart {
        if let running = starter.runningDaemon() {
            guard starter.parentOf(running) == ProcessParent.launchd, starter.launchAgentIsInstalled() else {
                return .alreadyRunningWithoutLaunchAgent
            }
            starter.startLaunchAgent()
            return .launchAgent
        }
        if starter.launchAgentIsInstalled() {
            starter.startLaunchAgent()
            return .launchAgent
        }
        return starter.spawnDetached() ? .spawnedOnItsOwn : .spawnedByThisCommand
    }

    private static func spawnDetached() -> Bool {
        guard let executablePath = ownExecutablePath() else { return false }
        if let spawned = ResponsibilityDisclaimingSpawn.spawn(
            executablePath: executablePath,
            arguments: [CommandName.daemon.rawValue],
            logPath: openDaemonLogPath(),
            disclaim: ResponsibilityDisclaimingSpawn.shouldDisclaim(
                executablePath: executablePath,
                accountHome: PrivacyProtectedFolder.accountHome()
            )
        ) {
            return spawned.disclaimed
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [CommandName.daemon.rawValue]
        process.standardInput = FileHandle.nullDevice
        if let logHandle = openDaemonLogForAppending() {
            process.standardOutput = logHandle
            process.standardError = logHandle
        }
        try? process.run()
        return false
    }

    private static func openDaemonLogPath() -> String {
        let logURL = PetPaths.daemonLogFile
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        return logURL.path
    }

    private static func ownExecutablePath() -> String? {
        if let bundleExecutablePath = Bundle.main.executablePath { return bundleExecutablePath }
        guard let invokedPath = ProcessInfo.processInfo.arguments.first else { return nil }
        return URL(fileURLWithPath: invokedPath).standardizedFileURL.path
    }

    private static func openDaemonLogForAppending() -> FileHandle? {
        let logURL = PetPaths.daemonLogFile
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: nil)
        }
        guard let logHandle = try? FileHandle(forWritingTo: logURL) else { return nil }
        logHandle.seekToEndOfFile()
        return logHandle
    }
}

package enum DaemonStart: Equatable {
    case launchAgent
    case alreadyRunningWithoutLaunchAgent
    case spawnedOnItsOwn
    case spawnedByThisCommand
}

enum ResponsibilityDisclaimingSpawn {
    private typealias SetDisclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32

    private static let disclaimSymbolName = "responsibility_spawnattrs_setdisclaim"
    private static let defaultSymbolScope = UnsafeMutableRawPointer(bitPattern: -2)
    private static let nullDevicePath = "/dev/null"

    struct Spawned: Equatable {
        let processIdentifier: pid_t
        let disclaimed: Bool
    }

    static func shouldDisclaim(executablePath: String, accountHome: String?) -> Bool {
        guard let accountHome else { return false }
        return !PrivacyProtectedFolder.contains(executablePath, accountHome: accountHome)
    }

    static func spawn(executablePath: String, arguments: [String], logPath: String, disclaim: Bool) -> Spawned? {
        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else { return nil }
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        var disclaimed = false
        if disclaim, let symbol = dlsym(defaultSymbolScope, disclaimSymbolName) {
            let setDisclaim = unsafeBitCast(symbol, to: SetDisclaim.self)
            disclaimed = setDisclaim(&attributes, 1) == 0
        }
        var fileActions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0 else { return nil }
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, nullDevicePath, O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, logPath, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        posix_spawn_file_actions_adddup2(&fileActions, STDOUT_FILENO, STDERR_FILENO)
        let argumentVector = ([executablePath] + arguments).map { argument in strdup(argument) } + [nil]
        defer { for argument in argumentVector { free(argument) } }
        var processIdentifier: pid_t = 0
        let status = posix_spawn(&processIdentifier, executablePath, &fileActions, &attributes, argumentVector, environ)
        guard status == 0 else { return nil }
        return Spawned(processIdentifier: processIdentifier, disclaimed: disclaimed)
    }
}

enum PrivacyProtectedFolder {
    private static let foldersInHome = [
        "Desktop",
        "Documents",
        "Downloads",
        "Library/Mobile Documents",
        "Library/CloudStorage"
    ]
    private static let volumesFolder = "/Volumes"

    static func contains(_ path: String, accountHome: String) -> Bool {
        let resolvedPath = resolved(path)
        let resolvedHome = resolved(accountHome)
        let folders = foldersInHome.map { name in resolvedHome + "/" + name } + [volumesFolder]
        return folders.contains { folder in resolvedPath == folder || resolvedPath.hasPrefix(folder + "/") }
    }

    static func accountHome() -> String? {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else { return nil }
        return String(cString: directory)
    }

    private static func resolved(_ path: String) -> String {
        var existing = URL(fileURLWithPath: path).standardizedFileURL
        var missingComponents: [String] = []
        while existing.path != "/" {
            if let real = realpath(existing.path, nil) {
                defer { free(real) }
                return missingComponents.reversed().reduce(String(cString: real)) { resolvedSoFar, component in
                    resolvedSoFar + "/" + component
                }
            }
            missingComponents.append(existing.lastPathComponent)
            existing.deleteLastPathComponent()
        }
        return existing.path + missingComponents.reversed().joined(separator: "/")
    }
}

enum OwnExecutable {
    static func isFoundThroughMainBundle() -> Bool {
        guard let bundle = CFBundleGetMainBundle() as CFBundle? else { return false }
        return CFBundleCopyExecutableURL(bundle) != nil
    }
}

enum ProcessParent {
    static let launchd: Int32 = 1

    static func of(_ processIdentifier: Int32) -> Int32? {
        var information = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processIdentifier]
        guard sysctl(&name, u_int(name.count), &information, &size, nil, 0) == 0, size > 0 else { return nil }
        return information.kp_eproc.e_ppid
    }
}
