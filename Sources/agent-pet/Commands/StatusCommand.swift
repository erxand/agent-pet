import Foundation

enum StatusCommand {
    private static let shortSessionIdLength = 8
    private static let columnGap = "  "
    private static let affirmative = "yes"
    private static let negative = "no"
    private static let noDaemonRunning = "none"

    private static let sessionColumnWidth = 10
    private static let labelColumnWidth = 24
    private static let accentColumnWidth = 8
    private static let enabledColumnWidth = 8
    private static let visibleColumnWidth = 8
    private static let moodColumnWidth = 11

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
            accent: "ACCENT",
            enabled: "ENABLED",
            visible: "VISIBLE",
            mood: "MOOD",
            alive: "ALIVE"
        )
    }

    private static func row(for session: PetSession, claudeSession: ClaudeSessionRecord?) -> String {
        columns(
            session: String(session.sessionId.prefix(shortSessionIdLength)),
            label: PetLabel.resolve(session: session, claudeSession: claudeSession),
            accent: session.resolvedAccent.rawValue,
            enabled: yesOrNo(session.enabled),
            visible: yesOrNo(session.visible),
            mood: session.mood.rawValue,
            alive: yesOrNo(ProcessLiveness.isAlive(session: session, claudeSession: claudeSession))
        )
    }

    private static func columns(
        session: String,
        label: String,
        accent: String,
        enabled: String,
        visible: String,
        mood: String,
        alive: String
    ) -> String {
        [
            padded(session, width: sessionColumnWidth),
            padded(label, width: labelColumnWidth),
            padded(accent, width: accentColumnWidth),
            padded(enabled, width: enabledColumnWidth),
            padded(visible, width: visibleColumnWidth),
            padded(mood, width: moodColumnWidth),
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
