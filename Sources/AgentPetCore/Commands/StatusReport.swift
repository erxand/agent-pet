import Foundation

struct StatusReport: Encodable {
    struct SessionEntry: Encodable {
        let sessionId: String
        let group: String
        let label: String
        let sprite: String
        let accent: String
        let agent: String
        let enabled: Bool
        let visible: Bool
        let mood: String
        let activeSubagents: Int
        let alive: Bool
        let pid: Int32?
        let focusTarget: String?
        let updatedAt: Double

        enum CodingKeys: String, CodingKey {
            case sessionId, group, label, sprite, accent, agent, enabled, visible, mood
            case activeSubagents, alive, pid, focusTarget, updatedAt
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(group, forKey: .group)
            try container.encode(label, forKey: .label)
            try container.encode(sprite, forKey: .sprite)
            try container.encode(accent, forKey: .accent)
            try container.encode(agent, forKey: .agent)
            try container.encode(enabled, forKey: .enabled)
            try container.encode(visible, forKey: .visible)
            try container.encode(mood, forKey: .mood)
            try container.encode(activeSubagents, forKey: .activeSubagents)
            try container.encode(alive, forKey: .alive)
            try container.encode(pid, forKey: .pid)
            try container.encode(focusTarget, forKey: .focusTarget)
            try container.encode(updatedAt, forKey: .updatedAt)
        }
    }

    let daemonPid: Int32?
    let sessions: [SessionEntry]

    enum CodingKeys: String, CodingKey {
        case daemonPid, sessions
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(daemonPid, forKey: .daemonPid)
        try container.encode(sessions, forKey: .sessions)
    }

    static func print(sessions: [PetSession], claudeSessions: [String: ClaudeSessionRecord]) -> Int32 {
        let report = StatusReport(
            daemonPid: StatusCommand.liveDaemonProcessIdentifier(),
            sessions: sessions.map { session in
                entry(for: session, claudeSession: claudeSessions[session.sessionId])
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let payload = try? encoder.encode(report) else { return CommandFeedback.reportUsage() }
        FileHandle.standardOutput.write(payload)
        FileHandle.standardOutput.write(Data("\n".utf8))
        return ExitCode.success
    }

    private static func entry(for session: PetSession, claudeSession: ClaudeSessionRecord?) -> SessionEntry {
        SessionEntry(
            sessionId: session.sessionId,
            group: session.sessionId,
            label: PetLabel.resolve(session: session, claudeSession: claudeSession),
            sprite: session.sprite ?? SpritePackLoader.defaultPackName,
            accent: session.resolvedAccent.rawValue,
            agent: session.agent.rawValue,
            enabled: session.enabled,
            visible: session.visible,
            mood: session.mood.rawValue,
            activeSubagents: session.activeSubagents.count,
            alive: ProcessLiveness.isAlive(session: session, claudeSession: claudeSession),
            pid: session.pid ?? claudeSession?.pid,
            focusTarget: session.focusTarget,
            updatedAt: session.updatedAt
        )
    }
}
