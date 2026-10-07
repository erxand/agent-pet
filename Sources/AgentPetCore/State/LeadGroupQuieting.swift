import Foundation

enum LeadGroupQuieting {
    static func hideReadyMembers(ofLead leadSessionId: String, store: PetSessionStore = PetSessionStore()) {
        guard let lead = store.load(sessionId: leadSessionId),
              lead.enabled,
              lead.leadsItsGroup,
              lead.isFlaggedOwner,
              lead.group != nil else { return }
        for member in store.list() where member.sessionId != lead.sessionId
            && member.petKey == lead.petKey
            && isLiveMember(member)
            && isQuietedWithTheLead(member) {
            PetTurnState.hide(sessionId: member.sessionId)
        }
    }

    static func isLiveMember(_ member: PetSession) -> Bool {
        member.enabled && (member.pid.map { processIdentifier in ProcessLiveness.isAlive(processIdentifier: processIdentifier) } ?? true)
    }

    static func isQuietedWithTheLead(_ member: PetSession) -> Bool {
        member.mood == .ready && (member.visible || member.held != nil)
    }
}
