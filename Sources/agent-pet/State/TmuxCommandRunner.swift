import Foundation

enum TmuxSubcommand: String {
    case selectWindow = "select-window"
    case selectPane = "select-pane"
    case switchClient = "switch-client"
    case displayMessage = "display-message"
    case sendKeys = "send-keys"
}

enum CommandSwitch: String, CaseIterable {
    case noColorSync = "--no-color-sync"
}

enum TmuxCommandRunner {
    static let targetFlag = "-t"
    static let printFlag = "-p"
    static let literalFlag = "-l"
    static let enterKeyName = "Enter"

    private static let environmentExecutablePath = "/usr/bin/env"
    private static let tmuxExecutableName = "tmux"

    static func run(subcommand: TmuxSubcommand, arguments: [String]) {
        let process = makeProcess(subcommand: subcommand, arguments: arguments)
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
        let process = makeProcess(subcommand: subcommand, arguments: arguments)
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

    private static func makeProcess(subcommand: TmuxSubcommand, arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: environmentExecutablePath)
        process.arguments = [tmuxExecutableName, subcommand.rawValue] + arguments
        process.standardInput = FileHandle.nullDevice
        return process
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

enum PromptBarColorSync {
    private static let colorCommandName = "/color"
    private static let defaultColorName = "default"

    static func applyAccent(_ accent: AccentColor, target: TmuxTarget) {
        typeLine("\(colorCommandName) \(accent.rawValue)", target: target)
    }

    static func applyDefaultColor(target: TmuxTarget) {
        typeLine("\(colorCommandName) \(defaultColorName)", target: target)
    }

    private static func typeLine(_ lineText: String, target: TmuxTarget) {
        TmuxCommandRunner.run(
            subcommand: .sendKeys,
            arguments: [
                TmuxCommandRunner.targetFlag,
                target.rawValue,
                TmuxCommandRunner.literalFlag,
                lineText
            ]
        )
        TmuxCommandRunner.run(
            subcommand: .sendKeys,
            arguments: [TmuxCommandRunner.targetFlag, target.rawValue, TmuxCommandRunner.enterKeyName]
        )
    }
}
