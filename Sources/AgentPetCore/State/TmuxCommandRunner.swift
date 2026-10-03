import Foundation

package enum TmuxSubcommand: String {
    case selectWindow = "select-window"
    case selectPane = "select-pane"
    case switchClient = "switch-client"
    case listClients = "list-clients"
    case displayMessage = "display-message"
    case sendKeys = "send-keys"
}

enum CommandSwitch: String, CaseIterable {
    case noColorSync = "--no-color-sync"
    case noClientSwitch = "--no-client-switch"
    case json = "--json"
    case owner = "--owner"
    case list = "--list"
    case dryRun = "--dry-run"
    case auto = "--auto"
}

package protocol TmuxCommandRunning {
    func run(subcommand: TmuxSubcommand, arguments: [String])
    func capture(subcommand: TmuxSubcommand, arguments: [String]) -> String?
}

package struct SystemTmux: TmuxCommandRunning {
    package init() {}

    package func run(subcommand: TmuxSubcommand, arguments: [String]) {
        TmuxCommandRunner.run(subcommand: subcommand, arguments: arguments)
    }

    package func capture(subcommand: TmuxSubcommand, arguments: [String]) -> String? {
        TmuxCommandRunner.capture(subcommand: subcommand, arguments: arguments)
    }
}

enum TmuxCommandRunner {
    static let targetFlag = "-t"
    static let printFlag = "-p"
    static let formatFlag = "-F"
    static let literalFlag = "-l"
    static let clientFlag = "-c"
    static let enterKeyName = "Enter"

    static let executablePath: String? = resolveExecutablePath()

    private static let tmuxExecutableName = "tmux"
    private static let wellKnownExecutablePaths = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/usr/bin/tmux"
    ]
    private static let searchPathSeparator: Character = ":"
    private static let pathComponentSeparator = "/"

    static func run(subcommand: TmuxSubcommand, arguments: [String]) {
        guard let process = makeProcess(subcommand: subcommand, arguments: arguments) else { return }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return
        }
        process.waitUntilExit()
    }

    static func capture(subcommand: TmuxSubcommand, arguments: [String]) -> String? {
        guard let process = makeProcess(subcommand: subcommand, arguments: arguments) else { return nil }
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let output = String(decoding: outputData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    private static func makeProcess(subcommand: TmuxSubcommand, arguments: [String]) -> Process? {
        guard let resolvedExecutablePath = executablePath else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedExecutablePath)
        process.arguments = [subcommand.rawValue] + arguments
        process.standardInput = FileHandle.nullDevice
        return process
    }

    private static func resolveExecutablePath() -> String? {
        let environment = ProcessInfo.processInfo.environment
        if let overriddenPath = environment[EnvironmentVariableName.tmuxExecutable],
           isExecutableFile(atPath: overriddenPath) {
            return overriddenPath
        }
        for candidatePath in wellKnownExecutablePaths where isExecutableFile(atPath: candidatePath) {
            return candidatePath
        }
        guard let searchPath = environment[EnvironmentVariableName.executableSearchPath] else { return nil }
        for directoryPath in searchPath.split(separator: searchPathSeparator) {
            let candidatePath = String(directoryPath) + pathComponentSeparator + tmuxExecutableName
            if isExecutableFile(atPath: candidatePath) {
                return candidatePath
            }
        }
        return nil
    }

    private static func isExecutableFile(atPath path: String) -> Bool {
        guard !path.isEmpty else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }
}

enum TmuxTargetResolver {
    private static let targetFormat = "#{session_name}:#{window_id}.#{pane_id}"

    static func resolveFromEnvironment() -> String? {
        let environment = ProcessInfo.processInfo.environment
        guard let paneIdentifier = environment[EnvironmentVariableName.tmuxPane], !paneIdentifier.isEmpty else {
            return nil
        }
        let resolved = TmuxCommandRunner.capture(
            subcommand: .displayMessage,
            arguments: [TmuxCommandRunner.printFlag, TmuxCommandRunner.targetFlag, paneIdentifier, targetFormat]
        )
        guard let resolved, TmuxTarget(rawValue: resolved) != nil else { return nil }
        return resolved
    }
}
