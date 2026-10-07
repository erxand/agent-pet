import Foundation

package struct PetDisplayItem {
    package let petKey: String
    package let session: PetSession
    package let label: String
    package let mood: PetMood
    package let message: String?
    package let bubbleCaption: String?
    package let memberSessionIds: [String]
    package let focusRequest: FocusRequest
}

package struct PetDisplayPlanner {
    private static let shortSessionIdLength = 4
    private static let memberCaptionPrefix = "#"
    private static let disambiguationSeparator = " "
    private static let memberPetKeySeparator = "#"

    private let grouping: PetGrouping
    private let disambiguatesLabels: Bool
    private let settleSeconds: TimeInterval
    private let holdsWhileBusy: Bool

    package init(
        grouping: PetGrouping,
        disambiguatesLabels: Bool = false,
        settleSeconds: TimeInterval = 0,
        holdsWhileBusy: Bool = false
    ) {
        self.grouping = grouping
        self.disambiguatesLabels = disambiguatesLabels
        self.settleSeconds = settleSeconds
        self.holdsWhileBusy = holdsWhileBusy
    }

    package func displayItems(
        records: [PetSession],
        claudeSessions: [String: ClaudeSessionRecord],
        now: TimeInterval = Date().timeIntervalSince1970,
        shownPetKeys: Set<String> = []
    ) -> [PetDisplayItem] {
        let liveMembers = records
            .filter { record in
                record.enabled
                    && ProcessLiveness.isAlive(session: record, claudeSession: claudeSessions[record.sessionId])
            }
            .sorted { leftRecord, rightRecord in leftRecord.updatedAt < rightRecord.updatedAt }
        let waitingGroups = grouping.groups(of: liveMembers)
            .map { group in
                settled(group, claudeSessions: claudeSessions, now: now, shownPetKeys: shownPetKeys)
            }
            .filter { group in group.isWaiting }
            .sorted { leftGroup, rightGroup in
                (leftGroup.waitingMembers.first?.updatedAt ?? 0) < (rightGroup.waitingMembers.first?.updatedAt ?? 0)
            }
        let items = waitingGroups.flatMap { group in self.items(for: group, claudeSessions: claudeSessions) }
        return disambiguatesLabels ? PetDisplayPlanner.disambiguated(items) : items
    }

    package func nextSettleDeadline(records: [PetSession], now: TimeInterval = Date().timeIntervalSince1970) -> TimeInterval? {
        records
            .compactMap { record -> TimeInterval? in
                guard record.enabled, record.visible, let waitingSince = record.waitingSince else { return nil }
                let deadline = waitingSince + settleSeconds
                return deadline > now ? deadline : nil
            }
            .min()
    }

    private func settled(
        _ group: PetGroup,
        claudeSessions: [String: ClaudeSessionRecord],
        now: TimeInterval,
        shownPetKeys: Set<String>
    ) -> PetGroup {
        let members = group.members.map { member -> PetSession in
            let isShown = shownPetKeys.contains(group.key)
                || shownPetKeys.contains(PetDisplayPlanner.memberPetKey(group: group.key, sessionId: member.sessionId))
            guard member.visible, let waitingSince = member.waitingSince else { return member }
            var heldBack = member
            if holdsWhileBusy,
               member.mood == .ready,
               claudeSessions[member.sessionId]?.wentBusy(since: waitingSince) == true {
                heldBack.visible = false
                heldBack.busy = true
                return heldBack
            }
            guard !isShown, now - waitingSince < settleSeconds else { return member }
            heldBack.visible = false
            return heldBack
        }
        return PetGroup(key: group.key, members: members)
    }

    private func items(for group: PetGroup, claudeSessions: [String: ClaudeSessionRecord]) -> [PetDisplayItem] {
        guard let lead = group.lead else {
            let plainItem = group.hasLostItsLead
                ? leaderlessItem(for: group, claudeSessions: claudeSessions)
                : item(for: group, claudeSessions: claudeSessions)
            return plainItem.map { item in [item] } ?? []
        }
        let askingMembers = group.askingMembersBesideTheLead
        let askingSessionIds = Set(askingMembers.map { member in member.sessionId })
        let memberItems = askingMembers.map { member in
            PetDisplayItem(
                petKey: PetDisplayPlanner.memberPetKey(group: group.key, sessionId: member.sessionId),
                session: member,
                label: PetLabel.resolve(session: member, claudeSession: claudeSessions[member.sessionId]),
                mood: member.mood,
                message: member.message,
                bubbleCaption: nil,
                memberSessionIds: [member.sessionId],
                focusRequest: FocusRequest(session: member, claudeSession: claudeSessions[member.sessionId])
            )
        }
        let leadWaiting = group.waitingMembers.filter { member in !askingSessionIds.contains(member.sessionId) }
        guard let mood = PetGroup.strongestMood(of: leadWaiting) else { return memberItems }
        let leadClaudeSession = claudeSessions[lead.sessionId]
        let leadItem = PetDisplayItem(
            petKey: group.key,
            session: lead,
            label: PetLabel.resolve(session: lead, claudeSession: leadClaudeSession),
            mood: mood,
            message: leadWaiting.contains { member in member.sessionId == lead.sessionId } ? lead.message : nil,
            bubbleCaption: nil,
            memberSessionIds: group.members
                .map { member in member.sessionId }
                .filter { sessionId in !askingSessionIds.contains(sessionId) },
            focusRequest: FocusRequest(session: lead, claudeSession: leadClaudeSession)
        )
        return [leadItem] + memberItems
    }

    private func leaderlessItem(for group: PetGroup, claudeSessions: [String: ClaudeSessionRecord]) -> PetDisplayItem? {
        guard let item = item(for: group, claudeSessions: claudeSessions),
              let waitingMember = group.mostRecentlyUpdatedWaitingMember else { return nil }
        return PetDisplayItem(
            petKey: item.petKey,
            session: item.session,
            label: PetLabel.resolve(session: waitingMember, claudeSession: claudeSessions[waitingMember.sessionId]),
            mood: item.mood,
            message: item.message,
            bubbleCaption: nil,
            memberSessionIds: item.memberSessionIds,
            focusRequest: item.focusRequest
        )
    }

    private func item(for group: PetGroup, claudeSessions: [String: ClaudeSessionRecord]) -> PetDisplayItem? {
        guard let owner = group.owner,
              let focusMember = group.focusMember,
              let mood = group.mood else { return nil }
        let waitingMember = group.mostRecentlyUpdatedWaitingMember
        let bubbleCaption = group.members.count > 1
            ? waitingMember.map { member in
                PetDisplayPlanner.memberName(member, claudeSession: claudeSessions[member.sessionId])
            }
            : nil
        let focusClaudeSession = claudeSessions[focusMember.sessionId]
        return PetDisplayItem(
            petKey: group.key,
            session: owner,
            label: PetLabel.resolve(session: owner, claudeSession: claudeSessions[owner.sessionId]),
            mood: mood,
            message: waitingMember?.message,
            bubbleCaption: bubbleCaption,
            memberSessionIds: group.members.map { member in member.sessionId },
            focusRequest: FocusRequest(session: focusMember, claudeSession: focusClaudeSession)
        )
    }

    package static func memberPetKey(group: String, sessionId: String) -> String {
        group + memberPetKeySeparator + sessionId
    }

    package static func memberName(_ member: PetSession, claudeSession: ClaudeSessionRecord?) -> String {
        for candidate in [member.nickname, member.label, claudeSession?.name] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return memberCaptionPrefix + String(member.sessionId.suffix(shortSessionIdLength))
    }

    private static func shownLabel(_ label: String) -> String {
        String(label.prefix(PetLabel.displayCharacterLimit))
    }

    private static func disambiguated(_ items: [PetDisplayItem]) -> [PetDisplayItem] {
        var countByLabel: [String: Int] = [:]
        for item in items {
            countByLabel[shownLabel(item.label), default: 0] += 1
        }
        let hintedPetKeys = petKeysTakingTheirHint(items, countByLabel: countByLabel)
        return items.map { item in
            guard (countByLabel[shownLabel(item.label)] ?? 0) > 1 else { return item }
            let distinction = hintedPetKeys.contains(item.petKey)
                ? item.session.disambiguator ?? ""
                : String(item.session.sessionId.suffix(shortSessionIdLength))
            let suffix = disambiguationSeparator + distinction
            let base = String(item.label.prefix(max(0, PetLabel.displayCharacterLimit - suffix.count)))
            return PetDisplayItem(
                petKey: item.petKey,
                session: item.session,
                label: base + suffix,
                mood: item.mood,
                message: item.message,
                bubbleCaption: item.bubbleCaption,
                memberSessionIds: item.memberSessionIds,
                focusRequest: item.focusRequest
            )
        }
    }

    private struct HintScope: Hashable {
        let label: String
        let scope: String
    }

    private static func petKeysTakingTheirHint(_ items: [PetDisplayItem], countByLabel: [String: Int]) -> Set<String> {
        var itemsByScope: [HintScope: [PetDisplayItem]] = [:]
        for item in items {
            let label = shownLabel(item.label)
            guard (countByLabel[label] ?? 0) > 1,
                  let scope = item.session.disambiguationScope, !scope.isEmpty else { continue }
            itemsByScope[HintScope(label: label, scope: scope), default: []].append(item)
        }
        var hinted: Set<String> = []
        for scopedItems in itemsByScope.values where scopedItems.count > 1 {
            var countByHint: [String: Int] = [:]
            for item in scopedItems {
                guard let hint = item.session.disambiguator, !hint.isEmpty else { continue }
                countByHint[hint, default: 0] += 1
            }
            for item in scopedItems {
                guard let hint = item.session.disambiguator, countByHint[hint] == 1 else { continue }
                hinted.insert(item.petKey)
            }
        }
        return hinted
    }
}
