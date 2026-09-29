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

        switch eventName {
        case .stop:
            handleStop(payload: payload, sessionId: sessionId)
        case .notification:
            handleNotification(payload: payload, sessionId: sessionId)
        case .subagentStart:
            guard let agentId = payload.agentId else { break }
            PetSubagentTracking.recordStart(sessionId: sessionId, agentId: agentId)
        case .subagentStop:
            guard let agentId = payload.agentId else { break }
            PetSubagentTracking.recordStop(sessionId: sessionId, agentId: agentId)
        case .userPromptSubmit:
            PetSubagentTracking.clear(sessionId: sessionId)
            PetTurnState.hide(sessionId: sessionId)
        case .preToolUse:
            PetTurnState.hide(sessionId: sessionId)
        case .sessionEnd:
            PetSessionStore().delete(sessionId: sessionId)
        }
        return ExitCode.success
    }

    private static func handleStop(payload: HookPayload, sessionId: String) {
        guard !PetTurnState.hasActiveSubagents(sessionId: sessionId) else {
            PetTurnState.hide(sessionId: sessionId)
            return
        }
        showAndEnsureDaemon(
            sessionId: sessionId,
            mood: .ready,
            message: firstLineSummary(of: payload.lastAssistantMessage)
        )
    }

    private static func handleNotification(payload: HookPayload, sessionId: String) {
        guard let rawNotificationType = payload.notificationType,
              let notificationType = HookNotificationType(rawValue: rawNotificationType) else { return }
        switch notificationType {
        case .permissionPrompt, .agentNeedsInput:
            showAndEnsureDaemon(sessionId: sessionId, mood: .needsInput, message: nil)
        }
    }

    private static func showAndEnsureDaemon(sessionId: String, mood: PetMood, message: String?) {
        guard PetTurnState.show(sessionId: sessionId, mood: mood, message: message) else { return }
        DaemonCommand.ensureRunning()
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
