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
        flaggedOwner ?? membersByEnrollment.first
    }

    private var membersByEnrollment: [PetSession] {
        members.sorted { leftMember, rightMember in
            if leftMember.enrollmentOrder != rightMember.enrollmentOrder {
                return leftMember.enrollmentOrder < rightMember.enrollmentOrder
            }
            return leftMember.sessionId < rightMember.sessionId
        }
    }

    package var lead: PetSession? {
        guard let flaggedOwner, flaggedOwner.leadsItsGroup else { return nil }
        return flaggedOwner
    }

    package var isLead: Bool {
        lead != nil
    }

    package var hasLostItsLead: Bool {
        flaggedOwner == nil && members.contains { member in member.leadsItsGroup }
    }

    package var flaggedOwner: PetSession? {
        membersByEnrollment.first { member in member.isFlaggedOwner }
    }

    package var askingMembersBesideTheLead: [PetSession] {
        guard let lead else { return [] }
        return waitingMembers.filter { member in
            member.sessionId != lead.sessionId && PetGroup.asksAtOnce.contains(member.mood)
        }
    }

    package var waitingMembers: [PetSession] {
        let holdsReady = holdsReadyWhileOthersWork
        return members.filter { member in
            member.visible && !(holdsReady && member.mood == .ready)
        }
    }

    package var isWaiting: Bool {
        !waitingMembers.isEmpty
    }

    package var hasWorkingMember: Bool {
        members.contains { member in member.isWorking }
    }

    private var holdsReadyWhileOthersWork: Bool {
        members.count > 1 && hasWorkingMember
    }

    package var mood: PetMood? {
        PetGroup.strongestMood(of: waitingMembers)
    }

    package static func strongestMood(of members: [PetSession]) -> PetMood? {
        let moods = Set(members.map { member in member.mood })
        return moodPrecedence.first { mood in moods.contains(mood) }
    }

    package var mostRecentlyUpdatedWaitingMember: PetSession? {
        waitingMembers.max { leftMember, rightMember in leftMember.updatedAt < rightMember.updatedAt }
    }

    package var focusMember: PetSession? {
        mostRecentlyUpdatedWaitingMember ?? owner
    }

    private static let moodPrecedence: [PetMood] = [.needsInput, .blocked, .ready]
    private static let asksAtOnce: Set<PetMood> = [.needsInput, .blocked]
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
