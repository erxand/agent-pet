import Darwin
import Foundation

enum SessionStartSource: String {
    case startup
    case resume
    case clear
    case compact

    var takesOverTheProcessPet: Bool {
        switch self {
        case .clear, .resume:
            return true
        case .startup, .compact:
            return false
        }
    }
}

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
        if let reclaimed = reclaimOwnRecord(sessionId: newSessionId, store: store) {
            return reclaimed
        }
        let candidates = store.list()
            .filter { record in record.sessionId != newSessionId && record.pid == processIdentifier }
            .sorted { leftRecord, rightRecord in leftRecord.updatedAt > rightRecord.updatedAt }
        guard let previous = candidates.first else { return nil }
        let handedOver = store.withLockedRecord(sessionId: newSessionId) { record -> PetSession? in
            guard record == nil else { return nil }
            let successor = successorRecord(of: previous, sessionId: newSessionId)
            record = successor
            return successor
        }
        guard let handedOver else { return nil }
        for candidate in candidates {
            store.withLockedRecord(sessionId: candidate.sessionId) { record in
                guard record?.pid == candidate.pid else { return }
                record = nil
            }
        }
        return handedOver
    }

    private static func reclaimOwnRecord(sessionId: String, store: PetSessionStore) -> PetSession? {
        guard store.load(sessionId: sessionId)?.handoverPendingSince != nil else { return nil }
        return store.withLockedRecord(sessionId: sessionId) { record -> PetSession? in
            guard var session = record, session.handoverPendingSince != nil else { return nil }
            session.handoverPendingSince = nil
            record = session
            return session
        }
    }

    static func owningProcessIdentifier(newSessionId: String, sessionSource: SessionSource, hookParent: Int32) -> Int32 {
        sessionSource.recordsBySessionId()[newSessionId]?.pid ?? hookParent
    }

    static func successorRecord(of previous: PetSession, sessionId: String) -> PetSession {
        var successor = previous
        successor.sessionId = sessionId
        successor.visible = false
        successor.held = nil
        successor.heldAt = nil
        successor.busy = nil
        successor.waitingSince = nil
        successor.handoverPendingSince = nil
        successor.mood = .ready
        successor.message = nil
        successor.activeSubagents = []
        successor.transcriptPath = nil
        successor.transcriptScanOffset = PetSession.initialTranscriptScanOffset
        successor.updatedAt = Date().timeIntervalSince1970
        return successor
    }
}
