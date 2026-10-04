import Foundation

enum HookEventLog {
    private static let filePermissions: mode_t = 0o644
    private static let shortSessionIdLength = 8
    private static let missingAgentIdPlaceholder = "-"
    private static let visibleFieldPrefix = "visible="
    private static let activeSubagentCountFieldPrefix = "agents="
    private static let toolNameFieldPrefix = "tool="
    private static let completedSubagentCountFieldPrefix = "completed="
    private static let interimSubagentCountFieldPrefix = "interim="
    private static let expiredSubagentCountFieldPrefix = "expired="
    private static let startedAtFieldPrefix = "startedAt="
    private static let skippedByteCountFieldPrefix = "skippedBytes="
    private static let subagentExpiredEntryName = "SubagentExpired"
    private static let transcriptReadTruncatedEntryName = "TranscriptReadTruncated"
    private static let fieldSeparator = " "
    private static let lineTerminator = "\n"

    static func append(
        event: HookEventName,
        sessionId: String,
        agentId: String?,
        result: PetHookResult,
        toolName: String?,
        detail: String? = nil,
        reportedCleanup: SubagentCleanupOutcome?
    ) {
        var fields = [
            event.rawValue,
            shortSessionId(sessionId),
            reportedAgentId(agentId),
            visibleFieldPrefix + String(result.snapshot.visible),
            activeSubagentCountFieldPrefix + String(result.snapshot.activeSubagentCount)
        ]
        if let toolName, !toolName.isEmpty {
            fields.append(toolNameFieldPrefix + toolName)
        }
        if let detail, !detail.isEmpty {
            fields.append(detail)
        }
        if let reportedCleanup, reportedCleanup.foundAnything {
            fields.append(completedSubagentCountFieldPrefix + String(reportedCleanup.completedSubagentIds.count))
            fields.append(interimSubagentCountFieldPrefix + String(reportedCleanup.interimSubagentIds.count))
            fields.append(expiredSubagentCountFieldPrefix + String(reportedCleanup.expiredSubagents.count))
        }
        appendEntry(fields: fields)
    }

    static func appendExpiredSubagent(sessionId: String, subagent: TrackedSubagent) {
        appendEntry(fields: [
            subagentExpiredEntryName,
            shortSessionId(sessionId),
            subagent.id,
            startedAtFieldPrefix + timestamp(Date(timeIntervalSince1970: subagent.startedAt))
        ])
    }

    static func appendTranscriptReadTruncated(sessionId: String, skippedByteCount: Int) {
        appendEntry(fields: [
            transcriptReadTruncatedEntryName,
            shortSessionId(sessionId),
            missingAgentIdPlaceholder,
            skippedByteCountFieldPrefix + String(skippedByteCount)
        ])
    }

    private static func appendEntry(fields: [String]) {
        LogFileTruncation.truncateIfOversized(at: PetPaths.hookLogFile)
        let line = ([timestamp(Date())] + fields).joined(separator: fieldSeparator) + lineTerminator
        appendLine(line)
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func shortSessionId(_ sessionId: String) -> String {
        String(sessionId.prefix(shortSessionIdLength))
    }

    private static func reportedAgentId(_ agentId: String?) -> String {
        guard let agentId, !agentId.isEmpty else { return missingAgentIdPlaceholder }
        return agentId
    }

    private static func appendLine(_ line: String) {
        PetPaths.createStateDirectoriesIfNeeded()
        let descriptor = open(
            PetPaths.hookLogFile.path,
            O_WRONLY | O_CREAT | O_APPEND,
            HookEventLog.filePermissions
        )
        guard descriptor >= 0 else { return }
        var bytes = Array(line.utf8)
        _ = write(descriptor, &bytes, bytes.count)
        close(descriptor)
    }
}
