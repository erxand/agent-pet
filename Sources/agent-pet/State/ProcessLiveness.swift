import Foundation

enum ProcessLiveness {
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
        if let claudeProcessIdentifier = claudeSession?.pid {
            return isAlive(processIdentifier: claudeProcessIdentifier)
        }
        return true
    }
}
