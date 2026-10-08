import Foundation

enum DaemonCommand {
    struct Foreground {
        var homeIsForeign: () -> Bool
        var prepare: () -> Void
        var otherLiveDaemon: () -> Int32?
        var ownExecutableIsFound: () -> Bool
        var claim: () -> Void
        var writeError: (String) -> Void

        static var live: Foreground {
            Foreground(
                homeIsForeign: AccountHome.isForeign,
                prepare: PetPaths.createStateDirectoriesIfNeeded,
                otherLiveDaemon: {
                    guard let recorded = DaemonProcessIdentifierFile.read(),
                          recorded != ProcessInfo.processInfo.processIdentifier,
                          ProcessLiveness.isAlive(processIdentifier: recorded) else { return nil }
                    return recorded
                },
                ownExecutableIsFound: { OwnExecutable.isFoundThroughMainBundle() },
                claim: {
                    let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
                    DaemonLogFile.truncateIfOversized()
                    DaemonLogFile.writeStartupLine(
                        processIdentifier: ownProcessIdentifier,
                        parentProcessIdentifier: getppid()
                    )
                    DaemonProcessIdentifierFile.write(processIdentifier: ownProcessIdentifier)
                },
                writeError: { line in
                    DaemonLogFile.truncateIfOversized()
                    CommandFeedback.writeToStandardError(line)
                }
            )
        }
    }

    static let ownExecutableMissingMessage = "the daemon cannot find its own executable through its main bundle,"
        + " so the window server would refuse it; not starting. macOS may have denied it the folder it is in."

    static func runInForeground(runOverlay: () -> Void) -> Int32 {
        runInForeground(using: .live, runOverlay: runOverlay)
    }

    static func runInForeground(using foreground: Foreground, runOverlay: () -> Void) -> Int32 {
        guard !foreground.homeIsForeign() else {
            foreground.writeError(AccountHome.refusalMessage())
            return ExitCode.success
        }
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
        if ensureRunningOnItsOwn() == .refusedForeignHome {
            ForeignHomeNotice.note(AccountHome.refusalMessage())
        }
    }

    @discardableResult
    static func ensureRunningAndSay(writeError: (String) -> Void = CommandFeedback.writeToStandardError) -> DaemonStart {
        let start = ensureRunningOnItsOwn()
        if start == .refusedForeignHome {
            writeError(AccountHome.refusalMessage())
        }
        return start
    }

    struct Starter {
        var homeIsForeign: () -> Bool
        var prepare: () -> Void = {}
        var launchAgentIsInstalled: () -> Bool
        var startLaunchAgent: () -> Void
        var runningDaemon: () -> Int32?
        var parentOf: (Int32) -> Int32?
        var spawnDetached: () -> Bool

        static var live: Starter {
            Starter(
                homeIsForeign: AccountHome.isForeign,
                prepare: PetPaths.createStateDirectoriesIfNeeded,
                launchAgentIsInstalled: { LaunchAgent.isInstalled },
                startLaunchAgent: { LaunchAgent.start() },
                runningDaemon: {
                    guard let recorded = DaemonProcessIdentifierFile.read(),
                          ProcessLiveness.isAlive(processIdentifier: recorded) else { return nil }
                    return recorded
                },
                parentOf: ProcessParent.of,
                spawnDetached: { DaemonCommand.spawnDetached() }
            )
        }
    }

    static func ensureRunningOnItsOwn() -> DaemonStart {
        ensureRunningOnItsOwn(using: .live)
    }

    static func ensureRunningOnItsOwn(using starter: Starter) -> DaemonStart {
        guard !starter.homeIsForeign() else { return .refusedForeignHome }
        starter.prepare()
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

    static func spawnDetached(
        homeIsForeign: () -> Bool = AccountHome.isForeign,
        spawn: () -> Bool = DaemonCommand.spawnOwnExecutable
    ) -> Bool {
        guard !homeIsForeign() else { return false }
        return spawn()
    }

    private static func spawnOwnExecutable() -> Bool {
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
        OwnExecutable.resolvedPath(
            mainBundleExecutablePath: Bundle.main.executablePath,
            invokedPath: ProcessInfo.processInfo.arguments.first
        )
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
    case refusedForeignHome
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

struct FileIdentity: Equatable {
    let device: UInt64
    let inode: UInt64

    static func of(_ path: String) -> FileIdentity? {
        var information = stat()
        guard stat(path, &information) == 0 else { return nil }
        return FileIdentity(device: UInt64(information.st_dev), inode: UInt64(information.st_ino))
    }
}

enum AccountHome {
    enum Verdict: Equatable {
        case own
        case foreign
        case accountHomeNotFound
    }

    struct Probes {
        var homeInUse: () -> String
        var passwordEntryHome: () -> String?
        var reentrantPasswordEntryHome: () -> String?
        var userName: () -> String
        var identity: (String) -> FileIdentity?

        static var live: Probes {
            Probes(
                homeInUse: { PetPaths.homeDirectory.path },
                passwordEntryHome: {
                    guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else { return nil }
                    return String(cString: directory)
                },
                reentrantPasswordEntryHome: reentrantPasswordEntryHome,
                userName: NSUserName,
                identity: FileIdentity.of
            )
        }

        private static func reentrantPasswordEntryHome() -> String? {
            var entry = passwd()
            var found: UnsafeMutablePointer<passwd>?
            var buffer = [CChar](repeating: 0, count: reentrantBufferSize)
            guard getpwuid_r(getuid(), &entry, &buffer, buffer.count, &found) == 0,
                  found != nil,
                  let directory = entry.pw_dir else { return nil }
            return String(cString: directory)
        }

        private static let reentrantBufferSize = 16_384
    }

    static let usersFolder = "/Users/"
    static let foreignHomeMessage = "the home folder in use is not this account's own, so no daemon is started for it:"
        + " a daemon there would share this account's launch agent and window server."
    static let accountHomeNotFoundMessage = "this account's home folder cannot be found (no password entry names one"
        + " that exists, and no /Users folder matches the user name), so no daemon is started."

    static func isForeign() -> Bool {
        verdict(.live) != .own
    }

    static func refusalMessage(_ probes: Probes = .live) -> String {
        verdict(probes) == .accountHomeNotFound ? accountHomeNotFoundMessage : foreignHomeMessage
    }

    static func verdict(_ probes: Probes) -> Verdict {
        guard let accountHome = home(probes) else { return .accountHomeNotFound }
        return isSameFolder(probes.homeInUse(), accountHome, identity: probes.identity) ? .own : .foreign
    }

    static func home(_ probes: Probes = .live) -> String? {
        let userName = probes.userName()
        let candidates = [
            probes.passwordEntryHome(),
            probes.reentrantPasswordEntryHome(),
            userName.isEmpty ? nil : usersFolder + userName
        ]
        return candidates.compactMap { candidate in candidate }.first { candidate in probes.identity(candidate) != nil }
    }

    static func isSameFolder(_ first: String, _ second: String, identity: (String) -> FileIdentity?) -> Bool {
        if let firstIdentity = identity(first), let secondIdentity = identity(second) {
            return firstIdentity == secondIdentity
        }
        return ResolvedPath.of(first) == ResolvedPath.of(second)
    }
}

enum ForeignHomeNotice {
    static let intervalInSeconds: TimeInterval = 3600
    private static let markerFileName = "foreign-home-noted"
    private static let logFileName = "daemon.log"

    @discardableResult
    static func note(_ message: String, stateDirectory: URL = PetPaths.stateDirectory, now: Date = Date()) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: stateDirectory.path) else { return false }
        let marker = stateDirectory.appendingPathComponent(markerFileName)
        if let noted = (try? fileManager.attributesOfItem(atPath: marker.path))?[.modificationDate] as? Date,
           noted <= now,
           now.timeIntervalSince(noted) < intervalInSeconds {
            return false
        }
        let log = stateDirectory.appendingPathComponent(logFileName)
        LogFileTruncation.truncateIfOversized(at: log)
        let line = ISO8601DateFormatter().string(from: now) + " agent-pet: " + message + "\n"
        if let handle = FileHandle(forWritingAtPath: log.path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            fileManager.createFile(atPath: log.path, contents: Data(line.utf8))
        }
        fileManager.createFile(atPath: marker.path, contents: nil)
        try? fileManager.setAttributes([.modificationDate: now], ofItemAtPath: marker.path)
        return true
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
    private static let foldersAtRoot = ["/Volumes", "/Network"]

    static func contains(_ path: String, accountHome: String) -> Bool {
        let resolvedPath = ResolvedPath.of(path)
        let resolvedHome = ResolvedPath.of(accountHome)
        let folders = foldersInHome.map { name in resolvedHome + "/" + name } + foldersAtRoot
        return folders.contains { folder in resolvedPath == folder || resolvedPath.hasPrefix(folder + "/") }
    }

    static func accountHome() -> String? {
        AccountHome.home()
    }
}

enum ResolvedPath {
    private static let dataVolumePrefix = "/System/Volumes/Data/"

    static func of(_ path: String) -> String {
        withoutDataVolume(resolvingExistingPart(of: path))
    }

    private static func withoutDataVolume(_ path: String) -> String {
        guard path.hasPrefix(dataVolumePrefix) else { return path }
        return "/" + path.dropFirst(dataVolumePrefix.count)
    }

    private static func resolvingExistingPart(of path: String) -> String {
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
    static func isFoundThroughMainBundle(
        mainBundle: () -> CFBundle? = { CFBundleGetMainBundle() },
        executableURL: (CFBundle) -> CFURL? = { bundle in CFBundleCopyExecutableURL(bundle) }
    ) -> Bool {
        guard let bundle = mainBundle() else { return false }
        return executableURL(bundle) != nil
    }

    // The real file behind this process, with symlinks resolved. The command on PATH is usually a
    // link to the executable inside AgentPet.app, and macOS finds an app's main bundle only from the
    // real path, so a daemon spawned through the link would run without the app's identity.
    static func resolvedPath(mainBundleExecutablePath: String?, invokedPath: String?) -> String? {
        guard let path = mainBundleExecutablePath ?? invokedPath else { return nil }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
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
