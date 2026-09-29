import Foundation

struct PetRecordSnapshot {
    let visible: Bool
    let activeSubagentCount: Int

    init(record: PetSession?) {
        visible = record?.visible ?? false
        activeSubagentCount = record?.activeSubagentIds.count ?? 0
    }
}

enum SubagentIdentity {
    case reported(String)
    case unreported
}

enum PetTurnState {
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
    ) -> PetRecordSnapshot {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            if record?.activeSubagentIds.isEmpty == false {
                markHidden(&record)
            } else {
                markVisible(&record, mood: mood, message: message)
            }
            return PetRecordSnapshot(record: record)
        }
    }

    @discardableResult
    static func hide(sessionId: String) -> PetRecordSnapshot {
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

    static func snapshot(sessionId: String) -> PetRecordSnapshot {
        PetRecordSnapshot(record: PetSessionStore().load(sessionId: sessionId))
    }

    private static func markVisible(_ record: inout PetSession?, mood: PetMood?, message: String?) {
        guard var session = record, session.enabled else { return }
        session.visible = true
        session.mood = mood ?? session.mood
        session.message = message
        session.updatedAt = Date().timeIntervalSince1970
        record = session
    }

    private static func markHidden(_ record: inout PetSession?) {
        guard var session = record, session.visible else { return }
        session.visible = false
        session.updatedAt = Date().timeIntervalSince1970
        record = session
    }
}

enum PetSubagentTracking {
    private static let unknownAgentIdPrefix = "unknown-"

    @discardableResult
    static func recordStartAndHide(sessionId: String, identity: SubagentIdentity) -> PetRecordSnapshot {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            guard var session = record else { return PetRecordSnapshot(record: record) }
            let agentId = startingAgentId(identity: identity, session: session)
            if !session.activeSubagentIds.contains(agentId) {
                session.activeSubagentIds.append(agentId)
            }
            session.visible = false
            session.updatedAt = Date().timeIntervalSince1970
            record = session
            return PetRecordSnapshot(record: record)
        }
    }

    @discardableResult
    static func recordStop(sessionId: String, identity: SubagentIdentity) -> PetRecordSnapshot {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            guard var session = record,
                  let agentId = stoppingAgentId(identity: identity, session: session),
                  session.activeSubagentIds.contains(agentId) else {
                return PetRecordSnapshot(record: record)
            }
            session.activeSubagentIds.removeAll { trackedAgentId in trackedAgentId == agentId }
            session.updatedAt = Date().timeIntervalSince1970
            record = session
            return PetRecordSnapshot(record: record)
        }
    }

    @discardableResult
    static func clear(sessionId: String) -> PetRecordSnapshot {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            guard var session = record, !session.activeSubagentIds.isEmpty else {
                return PetRecordSnapshot(record: record)
            }
            session.activeSubagentIds = []
            session.updatedAt = Date().timeIntervalSince1970
            record = session
            return PetRecordSnapshot(record: record)
        }
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
            return session.activeSubagentIds.last { trackedAgentId in
                trackedAgentId.hasPrefix(unknownAgentIdPrefix)
            }
        }
    }

    private static func nextUnknownAgentId(session: PetSession) -> String {
        var candidateNumber = 1
        var candidateId = unknownAgentIdPrefix + String(candidateNumber)
        while session.activeSubagentIds.contains(candidateId) {
            candidateNumber += 1
            candidateId = unknownAgentIdPrefix + String(candidateNumber)
        }
        return candidateId
    }
}
