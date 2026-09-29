import Foundation

enum HookEventLog {
    private static let filePermissions: mode_t = 0o644
    private static let shortSessionIdLength = 8
    private static let missingAgentIdPlaceholder = "-"
    private static let visibleFieldPrefix = "visible="
    private static let activeSubagentCountFieldPrefix = "agents="
    private static let fieldSeparator = " "
    private static let lineTerminator = "\n"

    static func append(
        event: HookEventName,
        sessionId: String,
        agentId: String?,
        snapshot: PetRecordSnapshot
    ) {
        LogFileTruncation.truncateIfOversized(at: PetPaths.hookLogFile)
        let fields = [
            ISO8601DateFormatter().string(from: Date()),
            event.rawValue,
            String(sessionId.prefix(shortSessionIdLength)),
            reportedAgentId(agentId),
            visibleFieldPrefix + String(snapshot.visible),
            activeSubagentCountFieldPrefix + String(snapshot.activeSubagentCount)
        ]
        appendLine(fields.joined(separator: fieldSeparator) + lineTerminator)
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
