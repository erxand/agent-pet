import Foundation

struct StatusReport: Encodable {
    struct SessionEntry: Encodable {
        let sessionId: String
        let group: String
        let owner: Bool
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
        let groupMode: String?
        let flaggedOwner: Bool
        let disambiguator: String?
        let disambiguationScope: String?

        enum CodingKeys: String, CodingKey {
            case sessionId, group, owner, label, sprite, accent, agent, enabled, visible, mood
            case activeSubagents, alive, pid, focusTarget, updatedAt
            case groupMode, flaggedOwner, disambiguator, disambiguationScope
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(group, forKey: .group)
            try container.encode(owner, forKey: .owner)
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
            try container.encode(groupMode, forKey: .groupMode)
            try container.encode(flaggedOwner, forKey: .flaggedOwner)
            try container.encode(disambiguator, forKey: .disambiguator)
            try container.encode(disambiguationScope, forKey: .disambiguationScope)
        }
    }

    let daemonPid: Int32?
    let sessions: [SessionEntry]
    let states: [String: PetStateFile.EffectiveEntry]

    enum CodingKeys: String, CodingKey {
        case daemonPid, sessions, states
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(daemonPid, forKey: .daemonPid)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(states, forKey: .states)
    }

    static func effectiveStates(daemonIsRunning: Bool) -> [String: PetStateFile.EffectiveEntry] {
        if daemonIsRunning, let reported = PetStateFile.loadEffective() {
            return reported
        }
        return PetStateFile.entries(of: PetEffectiveStates.resolve(commands: PetStateFile.loadCommands(), trigger: .none))
    }

    static func print(sessions: [PetSession], claudeSessions: [String: ClaudeSessionRecord]) -> Int32 {
        let ownerSessionIds = Set(
            LivePets.groups(records: sessions, claudeSessions: claudeSessions).compactMap { pet in pet.owner?.sessionId }
        )
        let daemonPid = StatusCommand.liveDaemonProcessIdentifier()
        let report = StatusReport(
            daemonPid: daemonPid,
            sessions: sessions.map { session in
                entry(
                    for: session,
                    claudeSession: claudeSessions[session.sessionId],
                    isOwner: ownerSessionIds.contains(session.sessionId)
                )
            },
            states: effectiveStates(daemonIsRunning: daemonPid != nil)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let payload = try? encoder.encode(report) else { return CommandFeedback.reportUsage() }
        FileHandle.standardOutput.write(payload)
        FileHandle.standardOutput.write(Data("\n".utf8))
        return ExitCode.success
    }

    private static func entry(for session: PetSession, claudeSession: ClaudeSessionRecord?, isOwner: Bool) -> SessionEntry {
        SessionEntry(
            sessionId: session.sessionId,
            group: session.petKey,
            owner: isOwner,
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
            updatedAt: session.updatedAt,
            groupMode: (session.groupMode ?? .shared).rawValue,
            flaggedOwner: session.isFlaggedOwner,
            disambiguator: session.disambiguator,
            disambiguationScope: session.disambiguationScope
        )
    }
}
