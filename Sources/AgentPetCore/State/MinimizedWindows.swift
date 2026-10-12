import Foundation

package struct MinimizedWindow: Equatable {
    package let title: String
    package let focusTargets: [String]

    package init(title: String, focusTargets: [String]) {
        self.title = title
        self.focusTargets = focusTargets
    }
}

package struct MinimizedWindows: Equatable {
    package static let none = MinimizedWindows(writerProcessIdentifier: nil, windows: [])

    package let writerProcessIdentifier: Int32?
    package let windows: [MinimizedWindow]

    package init(writerProcessIdentifier: Int32?, windows: [MinimizedWindow]) {
        self.writerProcessIdentifier = writerProcessIdentifier
        self.windows = windows
    }

    private struct MinimizedFile: Decodable {
        let pid: Int32?
        let windows: [RawWindow]?
    }

    private struct RawWindow: Decodable {
        let title: String?
        let focusTargets: [String]?
    }

    package var focusTargets: Set<String> {
        Set(windows.flatMap { window in window.focusTargets })
    }

    package func window(holding focusTarget: String?) -> MinimizedWindow? {
        guard let focusTarget else { return nil }
        return windows.first { window in window.focusTargets.contains(focusTarget) }
    }

    package static func read(file: URL = PetPaths.minimizedFile) -> MinimizedWindows {
        guard let payload = try? Data(contentsOf: file),
              let minimized = try? JSONDecoder().decode(MinimizedFile.self, from: payload),
              let writerProcessIdentifier = minimized.pid,
              ProcessLiveness.isAlive(processIdentifier: writerProcessIdentifier) else {
            return .none
        }
        let windows = (minimized.windows ?? []).compactMap { raw -> MinimizedWindow? in
            let targets = (raw.focusTargets ?? []).filter { target in !target.isEmpty }
            guard !targets.isEmpty else { return nil }
            return MinimizedWindow(title: raw.title ?? "", focusTargets: targets)
        }
        return MinimizedWindows(writerProcessIdentifier: writerProcessIdentifier, windows: windows)
    }

    package static func current(
        configuration: @autoclosure () -> AgentPetConfiguration = ConfigurationFile.load(),
        file: URL = PetPaths.minimizedFile
    ) -> MinimizedWindows {
        guard configuration().hidesWhenWindowMinimized else { return .none }
        return read(file: file)
    }

    package static func isMinimized(_ session: PetSession, minimizedTargets: Set<String>) -> Bool {
        guard let sessionTarget = session.focusTarget else { return false }
        return minimizedTargets.contains(sessionTarget)
    }
}
