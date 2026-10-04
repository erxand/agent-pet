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
        PetPaths.createStateDirectoriesIfNeeded()
        if LaunchAgent.isInstalled {
            LaunchAgent.start()
            return
        }
        if let recordedProcessIdentifier = DaemonProcessIdentifierFile.read(),
           ProcessLiveness.isAlive(processIdentifier: recordedProcessIdentifier) {
            return
        }
        spawnDetached()
    }

    private static func spawnDetached() {
        guard let executablePath = ownExecutablePath() else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [CommandName.daemon.rawValue]
        process.standardInput = FileHandle.nullDevice
        if let logHandle = openDaemonLogForAppending() {
            process.standardOutput = logHandle
            process.standardError = logHandle
        }
        try? process.run()
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
