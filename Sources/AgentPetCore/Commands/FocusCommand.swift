import Foundation

enum FocusCommand {
    static func run(flags: ParsedFlags) -> Int32 {
        guard let sessionId = SessionIdentifierResolver.resolve(flags: flags) else {
            return CommandFeedback.reportMissingSession()
        }
        let contracts = AgentPetContracts.loaded(focusCompletion: .waits)
        guard let session = PetSessionStore().load(sessionId: sessionId) else {
            switch contracts.configuration.focuser {
            case .tmuxIterm:
                return CommandFeedback.reportMissingTmuxTarget(sessionId)
            case .command:
                return CommandFeedback.reportMissingRecord(sessionId)
            }
        }
        let request = FocusRequest(
            session: session,
            claudeSession: nil,
            allowsClientSwitch: !flags.isPresent(.noClientSwitch)
        )
        if let unavailability = contracts.focuser.unavailability(for: request) {
            switch unavailability {
            case .missingTmuxTarget:
                return CommandFeedback.reportMissingTmuxTarget(sessionId)
            }
        }
        contracts.focuser.focus(request)
        return ExitCode.success
    }
}
