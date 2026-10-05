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

    /// `shownPetKeys` are the pets already up (not diving): the settle delay only holds a pet back from
    /// coming up, it never takes one down that is already showing.
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
                settled(group, claudeSessions: claudeSessions, now: now, isShown: shownPetKeys.contains(group.key))
            }
            .filter { group in group.isWaiting }
            .sorted { leftGroup, rightGroup in
                (leftGroup.waitingMembers.first?.updatedAt ?? 0) < (rightGroup.waitingMembers.first?.updatedAt ?? 0)
            }
        let items = waitingGroups.compactMap { group in item(for: group, claudeSessions: claudeSessions) }
        return disambiguatesLabels ? PetDisplayPlanner.disambiguated(items) : items
    }

    /// The earliest moment a pet the settle delay is holding back becomes due, so the daemon plans again then
    /// even when no file changed. `nil` when nothing is settling.
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
        isShown: Bool
    ) -> PetGroup {
        let members = group.members.map { member -> PetSession in
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
        return items.map { item in
            guard (countByLabel[shownLabel(item.label)] ?? 0) > 1 else { return item }
            let suffix = disambiguationSeparator + String(item.session.sessionId.suffix(shortSessionIdLength))
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
}
