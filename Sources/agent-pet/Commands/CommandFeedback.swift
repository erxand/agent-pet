import Foundation

enum CommandFeedback {
    private static let toolName = "agent-pet"

    static func reportMissingSession() -> Int32 {
        writeToStandardError(
            "no session id. Pass \(CommandFlag.session.rawValue) ID or set \(EnvironmentVariableName.claudeCodeSessionId)."
        )
        return ExitCode.usage
    }

    static func reportUnknownAccent(_ accentName: String) -> Int32 {
        writeToStandardError("unknown accent \(accentName). Valid values: \(joined(AccentColor.allCases.map { accent in accent.rawValue })).")
        return ExitCode.usage
    }

    static func reportUnknownMood(_ moodName: String) -> Int32 {
        writeToStandardError("unknown mood \(moodName). Valid values: \(joined(PetMood.allCases.map { mood in mood.rawValue })).")
        return ExitCode.usage
    }

    static func reportUnknownAgent(_ agentName: String) -> Int32 {
        writeToStandardError("unknown agent \(agentName). Valid values: \(joined(PetAgent.allCases.map { agent in agent.rawValue })).")
        return ExitCode.usage
    }

    static func reportUnknownProcessIdentifier(_ rawValue: String) -> Int32 {
        writeToStandardError("\(CommandFlag.pid.rawValue) must be a number, got \(rawValue).")
        return ExitCode.usage
    }

    static func reportUsage() -> Int32 {
        writeToStandardError(usageText)
        return ExitCode.usage
    }

    static func writeToStandardError(_ line: String) {
        FileHandle.standardError.write(Data("\(toolName): \(line)\n".utf8))
    }

    private static func joined(_ values: [String]) -> String {
        values.joined(separator: ", ")
    }

    private static let usageText = """
    usage: \(toolName) <command> [flags]

    commands:
      daemon           run the overlay in the foreground
      ensure-daemon    start the overlay daemon if it is not already running
      on               enroll this session and start the daemon
      off              disable this session
      show             make this session's pet visible
      hide             hide this session's pet
      remove           delete this session's record
      status           list enrolled sessions and the daemon pid
      hook             read one hook JSON object from stdin and dispatch
      preview          show a fake pet for a few seconds

    flags: \(CommandFlag.allCases.map { flag in flag.rawValue }.joined(separator: " "))
    switches: \(CommandSwitch.allCases.map { commandSwitch in commandSwitch.rawValue }.joined(separator: " "))
    """
}
