import Foundation

enum PetEnrollment {
    static func enroll(sessionId: String, overrides: PetIdentityOverrides, spriteStrategy: SpriteStrategy) -> PetSession {
        let enrolled = PetSessionStore().withLockedRecord(sessionId: sessionId) { record -> PetSession in
            var enrolled = overrides.applied(to: record ?? PetSession.newlyEnrolled(sessionId: sessionId))
            if record?.enabled != true {
                enrolled.visible = false
                enrolled.held = nil
                enrolled.heldAt = nil
            }
            enrolled.enabled = true
            if enrolled.sprite == nil {
                enrolled.sprite = spriteStrategy.spriteName(forNewSessionId: sessionId, group: enrolled.group)
            }
            if enrolled.accent == nil, let spriteName = enrolled.sprite {
                enrolled.accent = SpritePackAccent.accent(forPackNamed: spriteName)
                enrolled.accentFromPack = enrolled.accent == nil ? nil : true
            }
            if enrolled.tmuxTarget == nil {
                enrolled.tmuxTarget = TmuxTargetResolver.resolveFromEnvironment()
            }
            enrolled.updatedAt = Date().timeIntervalSince1970
            record = enrolled
            return enrolled
        }
        if overrides.owner { relinquishOwnership(of: enrolled) }
        return enrolled
    }

    static func disable(sessionId: String) -> PetSession? {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record -> PetSession? in
            guard var session = record else { return nil }
            session.enabled = false
            session.visible = false
            session.held = nil
            session.heldAt = nil
            session.updatedAt = Date().timeIntervalSince1970
            record = session
            return session
        }
    }

    @discardableResult
    static func applyOverrides(sessionId: String, overrides: PetIdentityOverrides) -> PetSession? {
        let updated = PetSessionStore().withLockedRecord(sessionId: sessionId) { record -> PetSession? in
            guard let existing = record, existing.enabled else { return nil }
            let updated = overrides.applied(to: existing)
            record = updated
            return updated
        }
        if overrides.owner, let updated { relinquishOwnership(of: updated) }
        return updated
    }

    private static func relinquishOwnership(of newOwner: PetSession) {
        let store = PetSessionStore()
        for other in store.list() where other.sessionId != newOwner.sessionId
            && other.petKey == newOwner.petKey
            && other.isFlaggedOwner {
            store.withLockedRecord(sessionId: other.sessionId) { record in
                guard var formerOwner = record, formerOwner.petKey == newOwner.petKey else { return }
                formerOwner.owner = nil
                record = formerOwner
            }
        }
    }
}
