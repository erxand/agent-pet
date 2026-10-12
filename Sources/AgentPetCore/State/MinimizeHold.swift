import Foundation

package struct MinimizeHoldChanges: Equatable {
    package var heldSessionIds: [String] = []
    package var endedSessionIds: [String] = []

    package init() {}

    package var isEmpty: Bool { heldSessionIds.isEmpty && endedSessionIds.isEmpty }
}

package enum MinimizeHold {
    @discardableResult
    package static func apply(
        minimizedTargets: Set<String>,
        focusedTarget: @autoclosure () -> String?,
        store: PetSessionStore = PetSessionStore()
    ) -> MinimizeHoldChanges {
        var changes = MinimizeHoldChanges()
        var focus: String??
        for record in store.list() {
            let minimized = MinimizedWindows.isMinimized(record, minimizedTargets: minimizedTargets)
            if record.visible && minimized {
                if PetTurnState.holdWhileMinimized(sessionId: record.sessionId, minimizedTargets: minimizedTargets, store: store) {
                    changes.heldSessionIds.append(record.sessionId)
                }
            } else if record.heldByMinimize == true && !minimized {
                let front = focus ?? focusedTarget()
                focus = front
                PetTurnState.endMinimizeHold(sessionId: record.sessionId, focusedTarget: front, store: store)
                changes.endedSessionIds.append(record.sessionId)
            }
        }
        return changes
    }

    package static func goesWithItsWindow(
        memberSessionIds: [String],
        records: [String: PetSession],
        minimizedTargets: Set<String>
    ) -> Bool {
        let shownFor = memberSessionIds.compactMap { sessionId in records[sessionId] }.filter { member in member.visible }
        guard !shownFor.isEmpty else { return false }
        return shownFor.allSatisfy { member in MinimizedWindows.isMinimized(member, minimizedTargets: minimizedTargets) }
    }
}
