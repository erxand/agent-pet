import Foundation

/// What a terminal says the user is looking at right now, from `~/.agent-pet/focus.json`.
///
/// A terminal integration writes `{"focusTarget": "<target>", "pid": <its own pid>}` whenever the
/// pane in front changes, and `"focusTarget": null` when nothing of its own is in front. The value
/// is compared with a record's `focusTarget`, so it means whatever the integration stamped there.
/// The writer's pid must be alive, so a terminal that crashed while focused holds nothing back.
package enum FocusedTarget {
    private struct FocusFile: Decodable {
        let focusTarget: String?
        let pid: Int32?
    }

    package static func current(file: URL = PetPaths.focusFile) -> String? {
        guard let payload = try? Data(contentsOf: file),
              let focus = try? JSONDecoder().decode(FocusFile.self, from: payload),
              let focusTarget = focus.focusTarget, !focusTarget.isEmpty,
              let writerProcessIdentifier = focus.pid,
              ProcessLiveness.isAlive(processIdentifier: writerProcessIdentifier) else {
            return nil
        }
        return focusTarget
    }

    package static func isInFront(_ session: PetSession, focusedTarget: String?) -> Bool {
        guard let focusedTarget, let sessionTarget = session.focusTarget else { return false }
        return sessionTarget == focusedTarget
    }
}
