import Foundation

enum ProcessLiveness {
    private static let missingClaudeSessionGraceInSeconds: TimeInterval = 30

    static func isAlive(processIdentifier: Int32) -> Bool {
        guard processIdentifier > 0 else { return false }
        if kill(processIdentifier, 0) == 0 { return true }
        return errno == EPERM
    }

    static func isAlive(session: PetSession, claudeSession: ClaudeSessionRecord?) -> Bool {
        if session.isPreview { return true }
        if let recordedProcessIdentifier = session.pid {
            return isAlive(processIdentifier: recordedProcessIdentifier)
        }
        switch session.agent {
        case .claudeCode:
            guard let claudeSession else { return isWithinMissingClaudeSessionGrace(session: session) }
            return isAlive(processIdentifier: claudeSession.pid)
        case .pi:
            return true
        }
    }

    private static func isWithinMissingClaudeSessionGrace(session: PetSession) -> Bool {
        let ageInSeconds = Date().timeIntervalSince1970 - session.updatedAt
        return ageInSeconds < missingClaudeSessionGraceInSeconds
    }
}
