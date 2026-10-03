import Foundation

enum FocusCommand {
    static func run(flags: ParsedFlags) -> Int32 {
        guard let sessionId = SessionIdentifierResolver.resolve(flags: flags) else {
            return CommandFeedback.reportMissingSession()
        }
        guard let session = PetSessionStore().load(sessionId: sessionId),
              let target = session.parsedTmuxTarget else {
            return CommandFeedback.reportMissingTmuxTarget(sessionId)
        }
        SessionFocuser.focus(
            tmuxTarget: target,
            allowsClientSwitch: !flags.isPresent(.noClientSwitch)
        )
        return ExitCode.success
    }
}
