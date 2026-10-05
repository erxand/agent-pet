import Foundation
import Testing
@testable import AgentPetCore

@Suite("a record kept for a handover that never comes")
struct HandoverExpiryTests {
    private func keptRecord(pendingFor ageInSeconds: TimeInterval) -> PetSession {
        var session = PetSession.newlyEnrolled(sessionId: "kept-session")
        session.pid = getpid()
        session.handoverPendingSince = Date().timeIntervalSince1970 - ageInSeconds
        return session
    }

    @Test func aRecentlyKeptRecordIsStillAlive() {
        #expect(ProcessLiveness.isAlive(session: keptRecord(pendingFor: 1), claudeSession: nil))
    }

    @Test func aKeptRecordNoSessionStartClaimedIsDeadAfterThirtySeconds() {
        #expect(!ProcessLiveness.isAlive(session: keptRecord(pendingFor: 31), claudeSession: nil))
    }
}
