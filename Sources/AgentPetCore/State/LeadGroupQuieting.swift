import Foundation

enum LeadGroupQuieting {
    static func hideReadyMembers(ofLead leadSessionId: String, store: PetSessionStore = PetSessionStore()) {
        guard let lead = store.load(sessionId: leadSessionId),
              lead.leadsItsGroup,
              lead.isFlaggedOwner,
              lead.group != nil else { return }
        for member in store.list() where member.sessionId != lead.sessionId
            && member.petKey == lead.petKey
            && isQuietedWithTheLead(member) {
            PetTurnState.hide(sessionId: member.sessionId)
        }
    }

    static func isQuietedWithTheLead(_ member: PetSession) -> Bool {
        member.visible && member.mood == .ready
    }
}
