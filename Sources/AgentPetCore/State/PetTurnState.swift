import Foundation

package struct PetRecordSnapshot {
    package let visible: Bool
    package let activeSubagentCount: Int

    init(record: PetSession?) {
        visible = record?.visible ?? false
        activeSubagentCount = record?.activeSubagents.count ?? 0
    }
}

struct PetHookResult {
    let snapshot: PetRecordSnapshot
    let cleanup: SubagentCleanupOutcome

    init(record: PetSession?, cleanup: SubagentCleanupOutcome = .nothingFound) {
        snapshot = PetRecordSnapshot(record: record)
        self.cleanup = cleanup
    }

    init(snapshot: PetRecordSnapshot) {
        self.snapshot = snapshot
        cleanup = .nothingFound
    }
}

enum SubagentIdentity {
    case reported(String)
    case unreported
}

enum SessionEndReason: String {
    case clear
    case resume
    case logout
    case promptInputExit = "prompt_input_exit"
    case other

    var continuesInSameProcess: Bool {
        switch self {
        case .clear, .resume:
            return true
        case .logout, .promptInputExit, .other:
            return false
        }
    }
}

package enum PetTurnState {
    @discardableResult
    static func show(sessionId: String, mood: PetMood?, message: String?) -> PetRecordSnapshot {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            markVisible(&record, mood: mood, message: message)
            return PetRecordSnapshot(record: record)
        }
    }

    @discardableResult
    static func showUnlessSubagentsActive(
        sessionId: String,
        mood: PetMood,
        message: String?
    ) -> PetHookResult {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            let cleanup = SubagentCleanup.apply(to: &record, now: Date().timeIntervalSince1970)
            if record?.activeSubagents.isEmpty == false {
                markHidden(&record)
            } else {
                markDone(&record)
                markVisible(&record, mood: mood, message: message)
            }
            return PetHookResult(record: record, cleanup: cleanup)
        }
    }

    @discardableResult
    static func hideAndMarkWorking(sessionId: String, keepsNeedsInput: Bool = false) -> PetRecordSnapshot {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            markWorking(&record)
            if !(keepsNeedsInput && record?.visible == true && record?.mood == .needsInput) {
                markHidden(&record)
            }
            return PetRecordSnapshot(record: record)
        }
    }

    @discardableResult
    static func markIdle(sessionId: String) -> PetRecordSnapshot {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            markDone(&record)
            return PetRecordSnapshot(record: record)
        }
    }

    @discardableResult
    package static func hide(sessionId: String) -> PetRecordSnapshot {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            markHidden(&record)
            return PetRecordSnapshot(record: record)
        }
    }

    @discardableResult
    static func remove(sessionId: String) -> PetRecordSnapshot {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            record = nil
            return PetRecordSnapshot(record: record)
        }
    }

    @discardableResult
    static func end(sessionId: String, reason: SessionEndReason?) -> PetRecordSnapshot {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            if reason?.continuesInSameProcess == true, var session = record, session.pid != nil {
                session.handoverPendingSince = Date().timeIntervalSince1970
                record = session
                markDone(&record)
                markHidden(&record)
            } else {
                record = nil
            }
            return PetRecordSnapshot(record: record)
        }
    }

    static func snapshot(sessionId: String) -> PetRecordSnapshot {
        PetRecordSnapshot(record: PetSessionStore().load(sessionId: sessionId))
    }

    private static func markVisible(_ record: inout PetSession?, mood: PetMood?, message: String?) {
        guard var session = record, session.enabled else { return }
        let now = Date().timeIntervalSince1970
        session.visible = true
        session.mood = mood ?? session.mood
        session.message = message
        session.waitingSince = now
        session.updatedAt = now
        record = session
    }

    private static func markWorking(_ record: inout PetSession?) {
        guard var session = record, session.busy != true else { return }
        session.busy = true
        record = session
    }

    private static func markDone(_ record: inout PetSession?) {
        guard var session = record, session.busy != nil else { return }
        session.busy = nil
        record = session
    }

    private static func markHidden(_ record: inout PetSession?) {
        guard var session = record, session.visible else { return }
        session.visible = false
        session.waitingSince = nil
        session.updatedAt = Date().timeIntervalSince1970
        record = session
    }
}

enum PetTranscriptTracking {
    static func recordTranscriptPath(sessionId: String, transcriptPath: String) {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            guard var session = record, session.transcriptPath != transcriptPath else { return }
            session.transcriptPath = transcriptPath
            session.transcriptScanOffset = PetSession.initialTranscriptScanOffset
            record = session
        }
    }
}

enum PetSubagentTracking {
    private static let unknownAgentIdPrefix = "unknown-"

    @discardableResult
    static func recordStartAndHide(sessionId: String, identity: SubagentIdentity) -> PetHookResult {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            let now = Date().timeIntervalSince1970
            let cleanup = SubagentCleanup.apply(to: &record, now: now)
            guard var session = record else { return PetHookResult(record: record, cleanup: cleanup) }
            session.busy = true
            let agentId = startingAgentId(identity: identity, session: session)
            if let existingIndex = session.activeSubagents.firstIndex(where: { trackedSubagent in
                trackedSubagent.id == agentId
            }) {
                session.activeSubagents[existingIndex].startedAt = now
            } else {
                session.activeSubagents.append(TrackedSubagent(id: agentId, startedAt: now))
            }
            session.visible = false
            session.updatedAt = now
            record = session
            return PetHookResult(record: record, cleanup: cleanup)
        }
    }

    @discardableResult
    static func recordStop(sessionId: String, identity: SubagentIdentity) -> PetHookResult {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            let now = Date().timeIntervalSince1970
            let cleanup = SubagentCleanup.apply(to: &record, now: now)
            if var session = record,
               let agentId = stoppingAgentId(identity: identity, session: session),
               isTracking(agentId, in: session) {
                session.activeSubagents.removeAll { trackedSubagent in trackedSubagent.id == agentId }
                session.updatedAt = now
                record = session
            }
            return PetHookResult(record: record, cleanup: cleanup)
        }
    }

    static func clear(sessionId: String) -> Int? {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record -> Int? in
            guard var session = record else { return nil }
            let droppedCount = session.activeSubagents.count
            guard !session.activeSubagents.isEmpty else { return droppedCount }
            session.activeSubagents = []
            session.updatedAt = Date().timeIntervalSince1970
            record = session
            return droppedCount
        }
    }

    private static func isTracking(_ agentId: String, in session: PetSession) -> Bool {
        session.activeSubagents.contains { trackedSubagent in trackedSubagent.id == agentId }
    }

    private static func startingAgentId(identity: SubagentIdentity, session: PetSession) -> String {
        switch identity {
        case .reported(let agentId):
            return agentId
        case .unreported:
            return nextUnknownAgentId(session: session)
        }
    }

    private static func stoppingAgentId(identity: SubagentIdentity, session: PetSession) -> String? {
        switch identity {
        case .reported(let agentId):
            return agentId
        case .unreported:
            return session.activeSubagents.last { trackedSubagent in
                trackedSubagent.id.hasPrefix(unknownAgentIdPrefix)
            }?.id
        }
    }

    private static func nextUnknownAgentId(session: PetSession) -> String {
        var candidateNumber = 1
        var candidateId = unknownAgentIdPrefix + String(candidateNumber)
        while isTracking(candidateId, in: session) {
            candidateNumber += 1
            candidateId = unknownAgentIdPrefix + String(candidateNumber)
        }
        return candidateId
    }
}
