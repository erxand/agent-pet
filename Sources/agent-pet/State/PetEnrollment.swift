import Foundation

enum PetEnrollment {
    static func enroll(sessionId: String, overrides: PetIdentityOverrides) -> PetSession {
        let store = PetSessionStore()
        let existing = store.load(sessionId: sessionId) ?? PetSession.newlyEnrolled(sessionId: sessionId)
        var enrolled = overrides.applied(to: existing)
        enrolled.enabled = true
        enrolled.visible = false
        if enrolled.tmuxTarget == nil {
            enrolled.tmuxTarget = TmuxTargetResolver.resolveFromEnvironment()
        }
        enrolled.updatedAt = Date().timeIntervalSince1970
        store.save(enrolled)
        return enrolled
    }

    static func disable(sessionId: String) -> PetSession? {
        let store = PetSessionStore()
        guard var session = store.load(sessionId: sessionId) else { return nil }
        session.enabled = false
        session.visible = false
        session.updatedAt = Date().timeIntervalSince1970
        store.save(session)
        return session
    }
}
