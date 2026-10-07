import Foundation

enum DaemonCommand {
    static func runInForeground(runOverlay: () -> Void) -> Int32 {
        PetPaths.createStateDirectoriesIfNeeded()
        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        if let recordedProcessIdentifier = DaemonProcessIdentifierFile.read(),
           recordedProcessIdentifier != ownProcessIdentifier,
           ProcessLiveness.isAlive(processIdentifier: recordedProcessIdentifier) {
            return ExitCode.success
        }
        DaemonLogFile.truncateIfOversized()
        DaemonLogFile.writeStartupLine(
            processIdentifier: ownProcessIdentifier,
            parentProcessIdentifier: getppid()
        )
        DaemonProcessIdentifierFile.write(processIdentifier: ownProcessIdentifier)
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
            )
        }
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
            logPath: openDaemonLogPath()
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

    static func spawn(executablePath: String, arguments: [String], logPath: String) -> Spawned? {
        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else { return nil }
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        var disclaimed = false
        if let symbol = dlsym(defaultSymbolScope, disclaimSymbolName) {
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
