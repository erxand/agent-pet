import Foundation

enum PetTurnState {
    @discardableResult
    static func show(sessionId: String, mood: PetMood, message: String?) -> Bool {
        let store = PetSessionStore()
        guard var session = store.load(sessionId: sessionId), session.enabled else { return false }
        session.visible = true
        session.mood = mood
        session.message = message
        session.updatedAt = Date().timeIntervalSince1970
        store.save(session)
        return true
    }

    static func hide(sessionId: String) {
        let store = PetSessionStore()
        guard var session = store.load(sessionId: sessionId) else { return }
        session.visible = false
        session.updatedAt = Date().timeIntervalSince1970
        store.save(session)
    }

    static func hasActiveSubagents(sessionId: String) -> Bool {
        guard let session = PetSessionStore().load(sessionId: sessionId) else { return false }
        return !session.activeSubagentIds.isEmpty
    }
}

enum PetSubagentTracking {
    static func recordStart(sessionId: String, agentId: String) {
        let store = PetSessionStore()
        guard var session = store.load(sessionId: sessionId) else { return }
        guard !session.activeSubagentIds.contains(agentId) else { return }
        session.activeSubagentIds.append(agentId)
        session.updatedAt = Date().timeIntervalSince1970
        store.save(session)
    }

    static func recordStop(sessionId: String, agentId: String) {
        let store = PetSessionStore()
        guard var session = store.load(sessionId: sessionId) else { return }
        guard session.activeSubagentIds.contains(agentId) else { return }
        session.activeSubagentIds.removeAll { trackedAgentId in trackedAgentId == agentId }
        session.updatedAt = Date().timeIntervalSince1970
        store.save(session)
    }

    static func clear(sessionId: String) {
        let store = PetSessionStore()
        guard var session = store.load(sessionId: sessionId) else { return }
        guard !session.activeSubagentIds.isEmpty else { return }
        session.activeSubagentIds = []
        session.updatedAt = Date().timeIntervalSince1970
        store.save(session)
    }
}
