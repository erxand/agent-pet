import Foundation

enum LeadGroupQuieting {
    static func hideReadyMembers(ofLead leadSessionId: String, store: PetSessionStore = PetSessionStore()) {
        guard let named = store.load(sessionId: leadSessionId),
              named.enabled,
              named.leadsItsGroup,
              named.group != nil else { return }
        let liveMembers = store.list().filter { member in member.petKey == named.petKey && isLiveMember(member) }
        guard PetGroup(key: named.petKey, members: liveMembers).lead?.sessionId == named.sessionId else { return }
        for member in liveMembers where member.sessionId != named.sessionId && isQuietedWithTheLead(member) {
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
