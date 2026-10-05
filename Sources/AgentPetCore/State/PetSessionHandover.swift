import Darwin
import Foundation

/// Where a `SessionStart` says the new session came from, from its `source`.
enum SessionStartSource: String {
    case startup
    case resume
    case clear
    case compact

    /// The session id changed inside a process that was already running, so the pet that process
    /// had is this session's now.
    var takesOverTheProcessPet: Bool {
        switch self {
        case .clear, .resume:
            return true
        case .startup, .compact:
            return false
        }
    }
}

/// `/clear` and `/resume` give a running Claude Code process a new session id. Its pet belongs to
/// the process, not to the id, so the new session takes over the record of that one process. The
/// process is the one Claude Code's own session file names for the new session id. Until Claude
/// Code has written that file, it is the process that ran the hook (Claude Code runs a hook as its
/// child). It is never any other ancestor: a Claude started from another Claude's Bash tool has
/// the parent Claude a few levels up, and must never take the parent's pet.
/// The identity (label, sprite, accent, group, owner, focus target, pid) moves; the turn state
/// (visible, busy, subagents, transcript) starts fresh, as it would for a new session.
enum PetSessionHandover {
    @discardableResult
    static func takeOver(
        newSessionId: String,
        sessionSource: SessionSource = AgentPetContracts.loaded().sessionSource,
        hookParent: Int32 = getppid()
    ) -> PetSession? {
        let processIdentifier = owningProcessIdentifier(
            newSessionId: newSessionId,
            sessionSource: sessionSource,
            hookParent: hookParent
        )
        let store = PetSessionStore()
        let candidates = store.list()
            .filter { record in record.sessionId != newSessionId && record.pid == processIdentifier }
            .sorted { leftRecord, rightRecord in leftRecord.updatedAt > rightRecord.updatedAt }
        guard let previous = candidates.first else { return nil }
        let handedOver = store.withLockedRecord(sessionId: newSessionId) { record -> PetSession in
            let successor = successorRecord(of: previous, sessionId: newSessionId)
            record = successor
            return successor
        }
        for candidate in candidates {
            store.withLockedRecord(sessionId: candidate.sessionId) { record in
                guard record?.pid == candidate.pid else { return }
                record = nil
            }
        }
        return handedOver
    }

    /// The Claude Code process the new session id runs in.
    static func owningProcessIdentifier(newSessionId: String, sessionSource: SessionSource, hookParent: Int32) -> Int32 {
        sessionSource.recordsBySessionId()[newSessionId]?.pid ?? hookParent
    }

    static func successorRecord(of previous: PetSession, sessionId: String) -> PetSession {
        var successor = previous
        successor.sessionId = sessionId
        successor.visible = false
        successor.busy = nil
        successor.waitingSince = nil
        successor.mood = .ready
        successor.message = nil
        successor.activeSubagents = []
        successor.handledHookEvents = nil
        successor.transcriptPath = nil
        successor.transcriptScanOffset = PetSession.initialTranscriptScanOffset
        successor.updatedAt = Date().timeIntervalSince1970
        return successor
    }
}
