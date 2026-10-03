import Foundation

package struct PetGroup: Equatable {
    package let key: String
    package let members: [PetSession]

    package var representative: PetSession? {
        members.first
    }
}

package protocol PetGrouping {
    func groups(of sessions: [PetSession]) -> [PetGroup]
}

package struct OnePetPerSessionGrouping: PetGrouping {
    package init() {}

    package func groups(of sessions: [PetSession]) -> [PetGroup] {
        sessions.map { session in PetGroup(key: session.sessionId, members: [session]) }
    }
}
