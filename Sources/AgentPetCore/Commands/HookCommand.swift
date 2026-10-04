import Foundation

enum HookEventName: String {
    case stop = "Stop"
    case notification = "Notification"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case sessionEnd = "SessionEnd"
    case sessionStart = "SessionStart"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
}

enum HookNotificationType: String {
    case permissionPrompt = "permission_prompt"
    case workerPermissionPrompt = "worker_permission_prompt"
    case agentNeedsInput = "agent_needs_input"
    case elicitationDialog = "elicitation_dialog"
    case elicitationUrlDialog = "elicitation_url_dialog"
    case idlePrompt = "idle_prompt"
}

struct HookPayload: Codable {
    let hookEventName: String?
    let sessionId: String?
    let agentId: String?
    let notificationType: String?
    let lastAssistantMessage: String?
    let transcriptPath: String?
    let toolName: String?
    let reason: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionId = "session_id"
        case agentId = "agent_id"
        case notificationType = "notification_type"
        case lastAssistantMessage = "last_assistant_message"
        case transcriptPath = "transcript_path"
        case toolName = "tool_name"
        case reason
        case source
    }
}

enum HookCommand {
    private static let messageCharacterLimit = 80
    private static let lineSeparator: Character = "\n"
    private static let notificationTypeFieldPrefix = "type="
    private static let reasonFieldPrefix = "reason="
    private static let sourceFieldPrefix = "source="

    static func run(flags: ParsedFlags) -> Int32 {
        let standardInputData = FileHandle.standardInput.readDataToEndOfFile()
        guard let payload = decodePayload(standardInputData) else { return ExitCode.success }
        guard let rawEventName = payload.hookEventName,
              let eventName = HookEventName(rawValue: rawEventName) else { return ExitCode.success }
        guard let sessionId = resolveSessionId(payload: payload, flags: flags) else { return ExitCode.success }
        if eventName == .sessionStart {
            return handleSessionStart(payload: payload, sessionId: sessionId)
        }
        guard PetSessionStore().hasRecord(sessionId: sessionId) else { return ExitCode.success }

        if let transcriptPath = payload.transcriptPath, !transcriptPath.isEmpty {
            PetTranscriptTracking.recordTranscriptPath(sessionId: sessionId, transcriptPath: transcriptPath)
        }
        let result = handle(
            eventName: eventName,
            payload: payload,
            payloadData: standardInputData,
            sessionId: sessionId
        )
        logCleanupDetails(result.cleanup, sessionId: sessionId)
        HookEventLog.append(
            event: eventName,
            sessionId: sessionId,
            agentId: payload.agentId,
            result: result,
            toolName: reportedToolName(eventName: eventName, payload: payload),
            detail: reportedDetail(eventName: eventName, payload: payload),
            reportedCleanup: reportedCleanup(eventName: eventName, result: result)
        )
        return ExitCode.success
    }

    /// The one event that may act for a session with no record: a `/clear` or `/resume` gives the
    /// running process a new session id, and the process's pet moves to it. Anything else, and a
    /// process with no pet, ends here with nothing written, like every other unenrolled event.
    private static func handleSessionStart(payload: HookPayload, sessionId: String) -> Int32 {
        guard let rawSource = payload.source,
              let source = SessionStartSource(rawValue: rawSource),
              source.takesOverTheProcessPet,
              let handedOver = PetSessionHandover.takeOver(newSessionId: sessionId) else {
            return ExitCode.success
        }
        HookEventLog.append(
            event: .sessionStart,
            sessionId: sessionId,
            agentId: nil,
            result: PetHookResult(record: handedOver),
            toolName: nil,
            detail: sourceFieldPrefix + rawSource,
            reportedCleanup: nil
        )
        return ExitCode.success
    }

    private static func handle(
        eventName: HookEventName,
        payload: HookPayload,
        payloadData: Data,
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
                identity: subagentIdentity(in: payload, payloadData: payloadData)
            )
        case .subagentStop:
            return PetSubagentTracking.recordStop(
                sessionId: sessionId,
                identity: subagentIdentity(in: payload, payloadData: payloadData)
            )
        case .userPromptSubmit:
            return PetHookResult(snapshot: PetTurnState.hideAndMarkWorking(sessionId: sessionId))
        case .preToolUse:
            return PetHookResult(snapshot: PetTurnState.hideAndMarkWorking(
                sessionId: sessionId,
                keepsNeedsInput: isFromSubagent(payload)
            ))
        case .sessionEnd:
            return PetHookResult(snapshot: PetTurnState.end(
                sessionId: sessionId,
                reason: payload.reason.flatMap { rawReason in SessionEndReason(rawValue: rawReason) }
            ))
        case .sessionStart:
            return PetHookResult(snapshot: PetTurnState.snapshot(sessionId: sessionId))
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
        case .permissionPrompt, .workerPermissionPrompt, .agentNeedsInput, .elicitationDialog, .elicitationUrlDialog:
            let snapshot = PetTurnState.show(sessionId: sessionId, mood: .needsInput, message: nil)
            ensureDaemonWhenVisible(snapshot: snapshot)
            return snapshot
        case .idlePrompt:
            return PetTurnState.markIdle(sessionId: sessionId)
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
        case .stop, .notification, .userPromptSubmit, .sessionEnd, .sessionStart, .subagentStart, .subagentStop:
            return nil
        }
    }

    private static func reportedDetail(eventName: HookEventName, payload: HookPayload) -> String? {
        switch eventName {
        case .notification:
            return payload.notificationType.map { notificationType in notificationTypeFieldPrefix + notificationType }
        case .sessionEnd:
            return payload.reason.map { reason in reasonFieldPrefix + reason }
        case .sessionStart:
            return payload.source.map { source in sourceFieldPrefix + source }
        case .stop, .userPromptSubmit, .preToolUse, .subagentStart, .subagentStop:
            return nil
        }
    }

    private static func isFromSubagent(_ payload: HookPayload) -> Bool {
        guard let agentId = payload.agentId else { return false }
        return !agentId.isEmpty
    }

    private static func reportedCleanup(eventName: HookEventName, result: PetHookResult) -> SubagentCleanupOutcome? {
        switch eventName {
        case .stop:
            return result.cleanup
        case .notification, .userPromptSubmit, .preToolUse, .sessionEnd, .sessionStart, .subagentStart, .subagentStop:
            return nil
        }
    }

    private static func ensureDaemonWhenVisible(snapshot: PetRecordSnapshot) {
        guard snapshot.visible else { return }
        DaemonCommand.ensureRunning()
    }

    private static func subagentIdentity(in payload: HookPayload, payloadData: Data) -> SubagentIdentity {
        guard let agentId = payload.agentId, !agentId.isEmpty else {
            return .unreported(fingerprint: HookEventDeduplication.fingerprint(ofPayload: payloadData))
        }
        return .reported(agentId)
    }

    private static func resolveSessionId(payload: HookPayload, flags: ParsedFlags) -> String? {
        if let fromPayload = payload.sessionId, !fromPayload.isEmpty { return fromPayload }
        return SessionIdentifierResolver.resolve(flags: flags)
    }

    private static func decodePayload(_ standardInputData: Data) -> HookPayload? {
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
