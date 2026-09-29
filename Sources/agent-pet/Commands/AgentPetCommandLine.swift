import Foundation

enum AgentPetCommandLine {
    static func run(arguments: [String]) -> Int32 {
        guard let commandToken = arguments.first,
              let command = CommandName(rawValue: commandToken) else {
            return CommandFeedback.reportUsage()
        }
        let flags = ParsedFlags(arguments: Array(arguments.dropFirst()))

        switch command {
        case .daemon:
            return DaemonCommand.runInForeground()
        case .ensureDaemon:
            DaemonCommand.ensureRunning()
            return ExitCode.success
        case .on:
            return SessionCommands.turnOn(flags: flags)
        case .off:
            return SessionCommands.turnOff(flags: flags)
        case .show:
            return SessionCommands.show(flags: flags)
        case .hide:
            return SessionCommands.hide(flags: flags)
        case .remove:
            return SessionCommands.remove(flags: flags)
        case .status:
            return StatusCommand.run()
        case .hook:
            return HookCommand.run(flags: flags)
        case .preview:
            return PreviewCommand.run(flags: flags)
        }
    }
}
