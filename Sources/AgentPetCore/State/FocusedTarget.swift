import Foundation

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
