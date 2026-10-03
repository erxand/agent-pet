import Foundation

package struct PetDisplayItem {
    package let petKey: String
    package let session: PetSession
    package let label: String
    package let focusRequest: FocusRequest
}

package struct PetDisplayPlanner {
    private let grouping: PetGrouping

    package init(grouping: PetGrouping) {
        self.grouping = grouping
    }

    package func displayItems(
        records: [PetSession],
        claudeSessions: [String: ClaudeSessionRecord]
    ) -> [PetDisplayItem] {
        let displayable = records
            .filter { record in
                record.enabled
                    && record.visible
                    && ProcessLiveness.isAlive(session: record, claudeSession: claudeSessions[record.sessionId])
            }
            .sorted { leftRecord, rightRecord in leftRecord.updatedAt < rightRecord.updatedAt }
        return grouping.groups(of: displayable).compactMap { group in
            guard let representative = group.representative else { return nil }
            let claudeSession = claudeSessions[representative.sessionId]
            return PetDisplayItem(
                petKey: group.key,
                session: representative,
                label: PetLabel.resolve(session: representative, claudeSession: claudeSession),
                focusRequest: FocusRequest(session: representative, claudeSession: claudeSession)
            )
        }
    }
}
