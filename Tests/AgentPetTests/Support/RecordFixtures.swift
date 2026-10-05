import Foundation

enum RecordFixtures {
    static let sessionId = "11111111-2222-3333-4444-555555555555"
    static let shortSessionId = "11111111"

    static func enrolled(
        sessionId: String = RecordFixtures.sessionId,
        visible: Bool = false,
        enabled: Bool = true,
        activeSubagents: [[String: Any]] = [],
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var record: [String: Any] = [
            "sessionId": sessionId,
            "enabled": enabled,
            "visible": visible,
            "mood": "ready",
            "agent": "claude-code",
            "pid": Int(getpid()),
            "activeSubagents": activeSubagents,
            "transcriptScanOffset": 0,
            "updatedAt": Date().timeIntervalSince1970
        ]
        record.merge(extra) { _, extraValue in extraValue }
        return record
    }

    static func trackedSubagent(_ agentId: String, startedAt: TimeInterval = Date().timeIntervalSince1970) -> [String: Any] {
        ["id": agentId, "startedAt": startedAt]
    }

    static func hookPayload(
        _ eventName: String,
        sessionId: String = RecordFixtures.sessionId,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var payload: [String: Any] = ["hook_event_name": eventName, "session_id": sessionId]
        payload.merge(extra) { _, extraValue in extraValue }
        return payload
    }

    static func finishedTaskNotificationLine(agentId: String) -> String {
        "{\"type\":\"user\",\"message\":{\"content\":\"<task-notification>\\n<task-id>\(agentId)</task-id>\\n<status>completed</status>\\n</task-notification>\"}}\n"
    }
}
