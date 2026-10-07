import Foundation

public enum AgentPetCommandLine {
    public static func run(arguments: [String], runOverlay: () -> Void) -> Int32 {
        run(arguments: arguments, runOverlay: runOverlay, runDemo: DemoCommand.reportOverlayUnavailable)
    }

    package static func run(
        arguments: [String],
        runOverlay: () -> Void,
        runDemo: (DemoRequest) -> Int32
    ) -> Int32 {
        guard let commandToken = arguments.first,
              let command = CommandName(rawValue: commandToken) else {
            return CommandFeedback.reportUsage()
        }
        let flags = ParsedFlags(arguments: Array(arguments.dropFirst()))

        switch command {
        case .daemon:
            return DaemonCommand.runInForeground(runOverlay: runOverlay)
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
        case .release:
            return SessionCommands.release(flags: flags)
        case .remove:
            return SessionCommands.remove(flags: flags)
        case .status:
            return StatusCommand.run(flags: flags)
        case .hook:
            return HookCommand.run(flags: flags)
        case .preview:
            return PreviewCommand.run(flags: flags)
        case .focus:
            return FocusCommand.run(flags: flags)
        case .clearSubagents:
            return SessionCommands.clearSubagents(flags: flags)
        case .scanTranscript:
            return ScanTranscriptCommand.run(flags: flags)
        case .render:
            return RenderCommand.run(flags: flags)
        case .packs:
            return PacksCommand.run(flags: flags)
        case .capabilities:
            return CapabilitiesCommand.run()
        case .demo:
            return DemoCommand.run(flags: flags, runDemo: runDemo)
        case .physics:
            return StateCommand.run(kind: .physics, arguments: Array(arguments.dropFirst()))
        case .input:
            return StateCommand.run(kind: .input, arguments: Array(arguments.dropFirst()))
        case .visibility:
            return StateCommand.run(kind: .visibility, arguments: Array(arguments.dropFirst()))
        case .level:
            return StateCommand.run(kind: .level, arguments: Array(arguments.dropFirst()))
        }
    }
}
