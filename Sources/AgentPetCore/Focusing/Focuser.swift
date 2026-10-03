import Foundation

package struct FocusRequest: Equatable {
    package let sessionId: String
    package let processIdentifier: Int32?
    package let focusTarget: String?
    package let group: String
    package let agent: PetAgent
    package let tmuxTarget: TmuxTarget?
    package let allowsClientSwitch: Bool

    package init(
        sessionId: String,
        processIdentifier: Int32?,
        focusTarget: String?,
        group: String,
        agent: PetAgent,
        tmuxTarget: TmuxTarget?,
        allowsClientSwitch: Bool
    ) {
        self.sessionId = sessionId
        self.processIdentifier = processIdentifier
        self.focusTarget = focusTarget
        self.group = group
        self.agent = agent
        self.tmuxTarget = tmuxTarget
        self.allowsClientSwitch = allowsClientSwitch
    }

    package init(
        session: PetSession,
        claudeSession: ClaudeSessionRecord?,
        allowsClientSwitch: Bool = TmuxItermFocuser.clientSwitchEnabledByDefault
    ) {
        self.init(
            sessionId: session.sessionId,
            processIdentifier: session.pid ?? claudeSession?.pid,
            focusTarget: session.focusTarget,
            group: session.petKey,
            agent: session.agent,
            tmuxTarget: session.parsedTmuxTarget ?? claudeSession?.tmux.flatMap { rawTarget in
                TmuxTarget(rawValue: rawTarget)
            },
            allowsClientSwitch: allowsClientSwitch
        )
    }
}

package enum FocusUnavailability: Equatable {
    case missingTmuxTarget
}

package protocol Focuser {
    func unavailability(for request: FocusRequest) -> FocusUnavailability?
    func focus(_ request: FocusRequest)
}
