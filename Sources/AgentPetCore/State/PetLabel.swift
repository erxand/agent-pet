import Foundation

package enum PetLabel {
    private static let fallback = "session"

    package static func resolve(session: PetSession, claudeSession: ClaudeSessionRecord?) -> String {
        for candidate in [session.nickname, session.label, claudeSession?.name] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        if let workingDirectory = claudeSession?.cwd, !workingDirectory.isEmpty {
            return URL(fileURLWithPath: workingDirectory).lastPathComponent
        }
        return fallback
    }
}
