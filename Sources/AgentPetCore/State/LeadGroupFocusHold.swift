import Foundation

enum LeadGroupFocusHold {
    static func isInFront(_ session: PetSession, focusedTarget: String?, store: PetSessionStore = PetSessionStore()) -> Bool {
        guard let focusedTarget else { return false }
        return leadGroupmates(of: session, store: store).contains { member in member.focusTarget == focusedTarget }
    }

    static func focusStaysInGroup(
        of sessionId: String,
        focusedTarget: String? = FocusedTarget.current(),
        store: PetSessionStore = PetSessionStore()
    ) -> Bool {
        guard let focusedTarget, let session = store.load(sessionId: sessionId) else { return false }
        return isInFront(session, focusedTarget: focusedTarget, store: store)
    }

    static func releaseHeldMembers(
        ofMember sessionId: String,
        grace: TimeInterval?,
        store: PetSessionStore = PetSessionStore()
    ) -> Bool {
        guard let session = store.load(sessionId: sessionId) else { return false }
        var anyVisible = false
        for member in leadGroupmates(of: session, store: store) where member.sessionId != session.sessionId
            && member.held == true
            && PetTurnState.release(sessionId: member.sessionId, grace: grace).visible {
            anyVisible = true
        }
        return anyVisible
    }

    private static func leadGroupmates(of session: PetSession, store: PetSessionStore) -> [PetSession] {
        guard session.group != nil else { return [] }
        let groupmates = store.list().filter { member in
            member.petKey == session.petKey && LeadGroupQuieting.isLiveMember(member)
        }
        let group = PetGroup(key: session.petKey, members: groupmates)
        guard group.lead != nil || group.hasLostItsLead else { return [] }
        return groupmates
    }
}
