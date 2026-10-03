import Foundation

enum StatusCommand {
    private static let shortSessionIdLength = 8
    private static let columnGap = "  "
    private static let affirmative = "yes"
    private static let negative = "no"
    private static let noDaemonRunning = "none"

    private static let sessionColumnWidth = 10
    private static let labelColumnWidth = 24
    private static let spriteColumnWidth = 10
    private static let accentColumnWidth = 8
    private static let enabledColumnWidth = 8
    private static let visibleColumnWidth = 8
    private static let moodColumnWidth = 11
    private static let agentsColumnWidth = 7

    static func run() -> Int32 {
        let sessions = PetSessionStore().list().sorted { leftSession, rightSession in
            leftSession.updatedAt < rightSession.updatedAt
        }
        let claudeSessions = ClaudeSessionDirectory().recordsBySessionId()

        print(headerRow())
        for session in sessions {
            let claudeSession = claudeSessions[session.sessionId]
            print(row(for: session, claudeSession: claudeSession))
        }
        print("daemon pid: \(daemonDescription())")
        return ExitCode.success
    }

    private static func headerRow() -> String {
        columns(
            session: "SESSION",
            label: "LABEL",
            sprite: "SPRITE",
            accent: "ACCENT",
            enabled: "ENABLED",
            visible: "VISIBLE",
            mood: "MOOD",
            agents: "AGENTS",
            alive: "ALIVE"
        )
    }

    private static func row(for session: PetSession, claudeSession: ClaudeSessionRecord?) -> String {
        columns(
            session: String(session.sessionId.prefix(shortSessionIdLength)),
            label: PetLabel.resolve(session: session, claudeSession: claudeSession),
            sprite: session.sprite ?? SpritePackLoader.defaultPackName,
            accent: session.resolvedAccent.rawValue,
            enabled: yesOrNo(session.enabled),
            visible: yesOrNo(session.visible),
            mood: session.mood.rawValue,
            agents: "\(session.activeSubagents.count)",
            alive: yesOrNo(ProcessLiveness.isAlive(session: session, claudeSession: claudeSession))
        )
    }

    private static func columns(
        session: String,
        label: String,
        sprite: String,
        accent: String,
        enabled: String,
        visible: String,
        mood: String,
        agents: String,
        alive: String
    ) -> String {
        [
            padded(session, width: sessionColumnWidth),
            padded(label, width: labelColumnWidth),
            padded(sprite, width: spriteColumnWidth),
            padded(accent, width: accentColumnWidth),
            padded(enabled, width: enabledColumnWidth),
            padded(visible, width: visibleColumnWidth),
            padded(mood, width: moodColumnWidth),
            padded(agents, width: agentsColumnWidth),
            alive
        ].joined(separator: columnGap)
    }

    private static func padded(_ text: String, width: Int) -> String {
        let clipped = String(text.prefix(width))
        return clipped.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    private static func yesOrNo(_ value: Bool) -> String {
        value ? affirmative : negative
    }

    private static func daemonDescription() -> String {
        guard let processIdentifier = DaemonProcessIdentifierFile.read(),
              ProcessLiveness.isAlive(processIdentifier: processIdentifier) else {
            return noDaemonRunning
        }
        return "\(processIdentifier)"
    }
}
