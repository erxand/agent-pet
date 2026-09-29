import Foundation

enum HookEventName: String {
    case stop = "Stop"
    case notification = "Notification"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case sessionEnd = "SessionEnd"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
}

enum HookNotificationType: String {
    case permissionPrompt = "permission_prompt"
    case agentNeedsInput = "agent_needs_input"
}

struct HookPayload: Codable {
    let hookEventName: String?
    let sessionId: String?
    let agentId: String?
    let notificationType: String?
    let lastAssistantMessage: String?

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionId = "session_id"
        case agentId = "agent_id"
        case notificationType = "notification_type"
        case lastAssistantMessage = "last_assistant_message"
    }
}

enum HookCommand {
    private static let messageCharacterLimit = 80
    private static let lineSeparator: Character = "\n"

    static func run(flags: ParsedFlags) -> Int32 {
        guard let payload = readPayload() else { return ExitCode.success }
        guard let rawEventName = payload.hookEventName,
              let eventName = HookEventName(rawValue: rawEventName) else { return ExitCode.success }
        guard let sessionId = resolveSessionId(payload: payload, flags: flags) else { return ExitCode.success }

        let snapshot = handle(eventName: eventName, payload: payload, sessionId: sessionId)
        HookEventLog.append(
            event: eventName,
            sessionId: sessionId,
            agentId: payload.agentId,
            snapshot: snapshot
        )
        return ExitCode.success
    }

    private static func handle(
        eventName: HookEventName,
        payload: HookPayload,
        sessionId: String
    ) -> PetRecordSnapshot {
        switch eventName {
        case .stop:
            return handleStop(payload: payload, sessionId: sessionId)
        case .notification:
            return handleNotification(payload: payload, sessionId: sessionId)
        case .subagentStart:
            return PetSubagentTracking.recordStartAndHide(
                sessionId: sessionId,
                identity: subagentIdentity(in: payload)
            )
        case .subagentStop:
            return PetSubagentTracking.recordStop(
                sessionId: sessionId,
                identity: subagentIdentity(in: payload)
            )
        case .userPromptSubmit:
            PetSubagentTracking.clear(sessionId: sessionId)
            return PetTurnState.hide(sessionId: sessionId)
        case .preToolUse:
            return PetTurnState.hide(sessionId: sessionId)
        case .sessionEnd:
            return PetTurnState.remove(sessionId: sessionId)
        }
    }

    private static func handleStop(payload: HookPayload, sessionId: String) -> PetRecordSnapshot {
        let snapshot = PetTurnState.showUnlessSubagentsActive(
            sessionId: sessionId,
            mood: .ready,
            message: firstLineSummary(of: payload.lastAssistantMessage)
        )
        ensureDaemonWhenVisible(snapshot: snapshot)
        return snapshot
    }

    private static func handleNotification(payload: HookPayload, sessionId: String) -> PetRecordSnapshot {
        guard let rawNotificationType = payload.notificationType,
              let notificationType = HookNotificationType(rawValue: rawNotificationType) else {
            return PetTurnState.snapshot(sessionId: sessionId)
        }
        switch notificationType {
        case .permissionPrompt, .agentNeedsInput:
            let snapshot = PetTurnState.show(sessionId: sessionId, mood: .needsInput, message: nil)
            ensureDaemonWhenVisible(snapshot: snapshot)
            return snapshot
        }
    }

    private static func ensureDaemonWhenVisible(snapshot: PetRecordSnapshot) {
        guard snapshot.visible else { return }
        DaemonCommand.ensureRunning()
    }

    private static func subagentIdentity(in payload: HookPayload) -> SubagentIdentity {
        guard let agentId = payload.agentId, !agentId.isEmpty else { return .unreported }
        return .reported(agentId)
    }

    private static func resolveSessionId(payload: HookPayload, flags: ParsedFlags) -> String? {
        if let fromPayload = payload.sessionId, !fromPayload.isEmpty { return fromPayload }
        return SessionIdentifierResolver.resolve(flags: flags)
    }

    private static func readPayload() -> HookPayload? {
        let standardInputData = FileHandle.standardInput.readDataToEndOfFile()
        guard !standardInputData.isEmpty else { return nil }
        return try? JSONDecoder().decode(HookPayload.self, from: standardInputData)
    }

    private static func firstLineSummary(of message: String?) -> String? {
        guard let message else { return nil }
        guard let firstLine = message.split(separator: lineSeparator).first else { return nil }
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(messageCharacterLimit))
    }
}
