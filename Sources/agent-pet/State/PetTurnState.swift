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
}
