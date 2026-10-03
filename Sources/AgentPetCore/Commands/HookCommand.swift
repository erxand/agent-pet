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
    let transcriptPath: String?
    let toolName: String?

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionId = "session_id"
        case agentId = "agent_id"
        case notificationType = "notification_type"
        case lastAssistantMessage = "last_assistant_message"
        case transcriptPath = "transcript_path"
        case toolName = "tool_name"
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

        if let transcriptPath = payload.transcriptPath, !transcriptPath.isEmpty {
            PetTranscriptTracking.recordTranscriptPath(sessionId: sessionId, transcriptPath: transcriptPath)
        }
        let result = handle(eventName: eventName, payload: payload, sessionId: sessionId)
        logCleanupDetails(result.cleanup, sessionId: sessionId)
        HookEventLog.append(
            event: eventName,
            sessionId: sessionId,
            agentId: payload.agentId,
            result: result,
            toolName: reportedToolName(eventName: eventName, payload: payload),
            reportedCleanup: reportedCleanup(eventName: eventName, result: result)
        )
        return ExitCode.success
    }

    private static func handle(
        eventName: HookEventName,
        payload: HookPayload,
        sessionId: String
    ) -> PetHookResult {
        switch eventName {
        case .stop:
            return handleStop(payload: payload, sessionId: sessionId)
        case .notification:
            return PetHookResult(snapshot: handleNotification(payload: payload, sessionId: sessionId))
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
        case .userPromptSubmit, .preToolUse:
            return PetHookResult(snapshot: PetTurnState.hide(sessionId: sessionId))
        case .sessionEnd:
            return PetHookResult(snapshot: PetTurnState.remove(sessionId: sessionId))
        }
    }

    private static func handleStop(payload: HookPayload, sessionId: String) -> PetHookResult {
        let result = PetTurnState.showUnlessSubagentsActive(
            sessionId: sessionId,
            mood: .ready,
            message: firstLineSummary(of: payload.lastAssistantMessage)
        )
        ensureDaemonWhenVisible(snapshot: result.snapshot)
        return result
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

    private static func logCleanupDetails(_ cleanup: SubagentCleanupOutcome, sessionId: String) {
        if cleanup.skippedTranscriptByteCount > TranscriptTail.noBytes {
            HookEventLog.appendTranscriptReadTruncated(
                sessionId: sessionId,
                skippedByteCount: cleanup.skippedTranscriptByteCount
            )
        }
        for expiredSubagent in cleanup.expiredSubagents {
            HookEventLog.appendExpiredSubagent(sessionId: sessionId, subagent: expiredSubagent)
        }
    }

    private static func reportedToolName(eventName: HookEventName, payload: HookPayload) -> String? {
        switch eventName {
        case .preToolUse:
            return payload.toolName
        case .stop, .notification, .userPromptSubmit, .sessionEnd, .subagentStart, .subagentStop:
            return nil
        }
    }

    private static func reportedCleanup(eventName: HookEventName, result: PetHookResult) -> SubagentCleanupOutcome? {
        switch eventName {
        case .stop:
            return result.cleanup
        case .notification, .userPromptSubmit, .preToolUse, .sessionEnd, .subagentStart, .subagentStop:
            return nil
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
