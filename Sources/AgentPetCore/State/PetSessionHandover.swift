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
/// the process, not to the id, so the new session takes the record over: the record whose `pid` is
/// one of the hook's nearest ancestors. Claude Code runs a hook as its child, at most through a
/// shell, so the walk stops three levels up: a Claude started from another Claude's Bash tool sits
/// further down than that from its parent, and must never take the parent's pet.
/// The identity (label, sprite, accent, group, owner, focus target, pid) moves; the turn state
/// (visible, held, busy, subagents, transcript) starts fresh, as it would for a new session.
enum PetSessionHandover {
    private static let maximumAncestorDepth = 3
    private static let firstUserProcessIdentifier: pid_t = 1

    @discardableResult
    static func takeOver(newSessionId: String, ancestors: [Int32] = PetSessionHandover.ancestorProcessIdentifiers()) -> PetSession? {
        let store = PetSessionStore()
        let candidates = store.list()
            .filter { record in
                record.sessionId != newSessionId
                    && record.pid.map { processIdentifier in ancestors.contains(processIdentifier) } == true
            }
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

    static func successorRecord(of previous: PetSession, sessionId: String) -> PetSession {
        var successor = previous
        successor.sessionId = sessionId
        successor.visible = false
        successor.held = nil
        successor.heldAt = nil
        successor.busy = nil
        successor.mood = .ready
        successor.message = nil
        successor.activeSubagents = []
        successor.handledHookEvents = nil
        successor.transcriptPath = nil
        successor.transcriptScanOffset = PetSession.initialTranscriptScanOffset
        successor.updatedAt = Date().timeIntervalSince1970
        return successor
    }

    static func ancestorProcessIdentifiers() -> [Int32] {
        var ancestors: [Int32] = []
        var current = getppid()
        while current > firstUserProcessIdentifier && ancestors.count < maximumAncestorDepth {
            ancestors.append(current)
            guard let parent = parentProcessIdentifier(of: current) else { break }
            current = parent
        }
        return ancestors
    }

    private static func parentProcessIdentifier(of processIdentifier: pid_t) -> pid_t? {
        var information = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var managementInformationBase: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processIdentifier]
        let status = managementInformationBase.withUnsafeMutableBufferPointer { buffer in
            sysctl(buffer.baseAddress, u_int(buffer.count), &information, &size, nil, 0)
        }
        guard status == 0, size > 0 else { return nil }
        return information.kp_eproc.e_ppid
    }
}
