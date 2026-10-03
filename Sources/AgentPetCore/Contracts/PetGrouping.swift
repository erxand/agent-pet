import Foundation

package struct PetGroup: Equatable {
    package let key: String
    package let members: [PetSession]

    package init(key: String, members: [PetSession]) {
        self.key = key
        self.members = members
    }

    package var representative: PetSession? {
        owner
    }

    package var owner: PetSession? {
        let byEnrollment = members.sorted { leftMember, rightMember in
            if leftMember.enrollmentOrder != rightMember.enrollmentOrder {
                return leftMember.enrollmentOrder < rightMember.enrollmentOrder
            }
            return leftMember.sessionId < rightMember.sessionId
        }
        return byEnrollment.first { member in member.isFlaggedOwner } ?? byEnrollment.first
    }

    package var waitingMembers: [PetSession] {
        members.filter { member in member.visible }
    }

    package var isWaiting: Bool {
        members.contains { member in member.visible }
    }

    package var mood: PetMood? {
        let waitingMoods = Set(waitingMembers.map { member in member.mood })
        return PetGroup.moodPrecedence.first { mood in waitingMoods.contains(mood) }
    }

    package var mostRecentlyUpdatedWaitingMember: PetSession? {
        waitingMembers.max { leftMember, rightMember in leftMember.updatedAt < rightMember.updatedAt }
    }

    package var focusMember: PetSession? {
        mostRecentlyUpdatedWaitingMember ?? owner
    }

    private static let moodPrecedence: [PetMood] = [.needsInput, .blocked, .ready]
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

package struct SharedKeyGrouping: PetGrouping {
    package init() {}

    package func groups(of sessions: [PetSession]) -> [PetGroup] {
        var keysInOrder: [String] = []
        var membersByKey: [String: [PetSession]] = [:]
        for session in sessions {
            if membersByKey[session.petKey] == nil { keysInOrder.append(session.petKey) }
            membersByKey[session.petKey, default: []].append(session)
        }
        return keysInOrder.map { key in PetGroup(key: key, members: membersByKey[key] ?? []) }
    }
}

package enum LivePets {
    package static func groups(
        records: [PetSession],
        claudeSessions: [String: ClaudeSessionRecord]
    ) -> [PetGroup] {
        let liveMembers = records.filter { record in
            record.enabled
                && ProcessLiveness.isAlive(session: record, claudeSession: claudeSessions[record.sessionId])
        }
        return SharedKeyGrouping().groups(of: liveMembers)
    }
}
