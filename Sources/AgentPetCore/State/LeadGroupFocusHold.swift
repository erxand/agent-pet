import Foundation

enum LeadGroupFocusHold {
    static func isInFront(_ session: PetSession, focusedTarget: String?, store: PetSessionStore = PetSessionStore()) -> Bool {
        guard let focusedTarget, session.group != nil else { return false }
        let groupmates = store.list().filter { member in member.petKey == session.petKey }
        guard groupmates.contains(where: { member in member.leadsItsGroup }) else { return false }
        return groupmates.contains { member in member.focusTarget == focusedTarget }
    }

    static func releaseHeldMembers(
        ofLead leadSessionId: String,
        grace: TimeInterval?,
        store: PetSessionStore = PetSessionStore()
    ) -> Bool {
        guard let lead = store.load(sessionId: leadSessionId),
              lead.leadsItsGroup,
              lead.isFlaggedOwner,
              lead.group != nil else { return false }
        var anyVisible = false
        for member in store.list() where member.sessionId != lead.sessionId
            && member.petKey == lead.petKey
            && member.held == true
            && PetTurnState.release(sessionId: member.sessionId, grace: grace).visible {
            anyVisible = true
        }
        return anyVisible
    }
}
