import Foundation

enum PetEnrollment {
    static func enroll(sessionId: String, overrides: PetIdentityOverrides) -> PetSession {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record -> PetSession in
            var enrolled = overrides.applied(to: record ?? PetSession.newlyEnrolled(sessionId: sessionId))
            enrolled.enabled = true
            enrolled.visible = false
            if enrolled.tmuxTarget == nil {
                enrolled.tmuxTarget = TmuxTargetResolver.resolveFromEnvironment()
            }
            enrolled.updatedAt = Date().timeIntervalSince1970
            record = enrolled
            return enrolled
        }
    }

    static func disable(sessionId: String) -> PetSession? {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record -> PetSession? in
            guard var session = record else { return nil }
            session.enabled = false
            session.visible = false
            session.updatedAt = Date().timeIntervalSince1970
            record = session
            return session
        }
    }

    @discardableResult
    static func applyOverrides(sessionId: String, overrides: PetIdentityOverrides) -> PetSession? {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record -> PetSession? in
            guard let existing = record, existing.enabled else { return nil }
            let updated = overrides.applied(to: existing)
            record = updated
            return updated
        }
    }
}
