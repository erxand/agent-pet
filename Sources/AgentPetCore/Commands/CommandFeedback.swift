import Foundation

package enum CommandFeedback {
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

    static func reportInvalidByteOffset(_ rawValue: String) -> Int32 {
        writeToStandardError("\(CommandFlag.from.rawValue) must be a byte offset of 0 or more, got \(rawValue).")
        return ExitCode.usage
    }

    static func reportUnknownGroupMode(_ rawValue: String) -> Int32 {
        writeToStandardError("unknown group mode \(rawValue). Valid values: \(joined(PetGroupMode.allCases.map { groupMode in groupMode.rawValue })).")
        return ExitCode.usage
    }

    static func reportMissingTranscriptPath() -> Int32 {
        writeToStandardError("no transcript. Pass \(CommandFlag.path.rawValue) FILE.")
        return ExitCode.usage
    }

    static func reportUnreadableTranscript(_ path: String) -> Int32 {
        writeToStandardError("cannot read transcript \(path).")
        return ExitCode.usage
    }

    static func reportMissingTmuxTarget(_ sessionId: String) -> Int32 {
        writeToStandardError("no tmux target for session \(sessionId).")
        return ExitCode.usage
    }

    static func reportMissingRecord(_ sessionId: String) -> Int32 {
        writeToStandardError("no record for session \(sessionId).")
        return ExitCode.usage
    }

    static func reportMissingPack() -> Int32 {
        writeToStandardError("no pack. Pass \(CommandFlag.pack.rawValue) NAME.")
        return ExitCode.usage
    }

    static func reportUnknownPack(_ packName: String) -> Int32 {
        writeToStandardError("no sprite pack named \(packName).")
        return ExitCode.usage
    }

    static func reportUnknownAnimation(_ animationName: String) -> Int32 {
        writeToStandardError("unknown animation \(animationName). Valid values: \(joined(SpriteAnimationName.allCases.map { animation in animation.rawValue })).")
        return ExitCode.usage
    }

    static func reportUnknownFrame(_ rawValue: String, animation: SpriteAnimationName, frameCount: Int) -> Int32 {
        writeToStandardError("\(CommandFlag.frame.rawValue) \(rawValue) is not a frame of \(animation.rawValue), which has \(frameCount).")
        return ExitCode.usage
    }

    static func reportUnknownScene(_ sceneName: String) -> Int32 {
        writeToStandardError("unknown scene \(sceneName). Valid values: \(joined(DemoSceneName.allCases.map { name in name.rawValue })).")
        return ExitCode.usage
    }

    static func reportInvalidSpeed(_ rawValue: String) -> Int32 {
        writeToStandardError("\(CommandFlag.speed.rawValue) must be a number above 0, not \(rawValue).")
        return ExitCode.usage
    }

    static func reportDemoUnavailable() -> Int32 {
        writeToStandardError("the demo needs the overlay. This build of the command line does not have it.")
        return ExitCode.usage
    }

    static func reportUsage() -> Int32 {
        writeToStandardError(usageText)
        return ExitCode.usage
    }

    package static func writeToStandardError(_ line: String) {
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
      focus            jump to this session's tmux pane and terminal tab
      clear-subagents  forget every subagent this session is tracking as running
      scan-transcript  diagnostic: print every subagent completion found in a transcript file
      render           print a sprite pack frame to the terminal in truecolor half blocks
      packs            list installed sprite packs with accent, reserved, and live pet count
      capabilities     print one word per line naming each feature this build has
      dock-access      say whether the daemon may read the Dock's exact frame; --ask has the daemon ask macOS
      demo             play a short tour on the desktop. It changes no session.
      physics          ground | float | auto: float makes every pet drift and spin, ground lands them
      input            on | off | auto: off makes every pet click-through and never take focus
      visibility       shown | hidden | auto: hidden sends every pet under, records untouched
      level            normal | above <bundle id> | auto: draw pets just above that app's windows

    flags: \(CommandFlag.allCases.map { flag in flag.rawValue }.joined(separator: " "))
    switches: \(CommandSwitch.allCases.map { commandSwitch in commandSwitch.rawValue }.joined(separator: " "))
    """
}
