import Foundation

package protocol SessionSource {
    func recordsBySessionId() -> [String: ClaudeSessionRecord]
    func signature() -> SessionSourceSignature
    func recordsBySessionId(in signature: SessionSourceSignature) -> [String: ClaudeSessionRecord]
    func watchedDirectories() -> [URL]
}

extension SessionSource {
    package func watchedDirectories() -> [URL] {
        []
    }

    package func recordsBySessionId(in signature: SessionSourceSignature) -> [String: ClaudeSessionRecord] {
        recordsBySessionId()
    }
}

package struct SessionSourceSignature: Equatable {
    let directories: [URL]
    let directorySignatures: [SessionsDirectorySignature]
}

package struct DirectorySessionSource: SessionSource {
    private let patterns: [String]
    private let homeDirectory: URL

    package init(patterns: [String], homeDirectory: URL = PetPaths.homeDirectory) {
        self.patterns = patterns
        self.homeDirectory = homeDirectory
    }

    package func directories() -> [URL] {
        var seenPaths: Set<String> = []
        var expanded: [URL] = []
        for pattern in patterns {
            for directory in SessionDirectoryPattern.expand(pattern, homeDirectory: homeDirectory)
            where seenPaths.insert(directory.standardizedFileURL.path).inserted {
                expanded.append(directory)
            }
        }
        return expanded
    }

    package func watchedDirectories() -> [URL] {
        directories()
    }

    package func recordsBySessionId() -> [String: ClaudeSessionRecord] {
        records(in: directories())
    }

    package func recordsBySessionId(in signature: SessionSourceSignature) -> [String: ClaudeSessionRecord] {
        records(in: signature.directories)
    }

    private func records(in directories: [URL]) -> [String: ClaudeSessionRecord] {
        var merged: [String: ClaudeSessionRecord] = [:]
        for directory in directories {
            for (sessionId, record) in ClaudeSessionDirectory(directory: directory).recordsBySessionId()
            where merged[sessionId] == nil {
                merged[sessionId] = record
            }
        }
        return merged
    }

    package func signature() -> SessionSourceSignature {
        let watched = directories()
        return SessionSourceSignature(
            directories: watched,
            directorySignatures: watched.map { directory in SessionsDirectorySignature.current(directory: directory) }
        )
    }
}

package enum SessionDirectoryPattern {
    private static let homePrefix = "~"
    private static let pathSeparator: Character = "/"
    private static let rootPath = "/"
    private static let wildcardCharacters: Set<Character> = ["*", "?", "["]

    package static func expand(_ pattern: String, homeDirectory: URL) -> [URL] {
        let absolutePattern = expandingHome(in: pattern, homeDirectory: homeDirectory)
        guard absolutePattern.hasPrefix(rootPath) else { return [] }
        var candidates = [URL(fileURLWithPath: rootPath, isDirectory: true)]
        for component in absolutePattern.split(separator: pathSeparator).map({ component in String(component) }) {
            candidates = candidates.flatMap { parent in matches(of: component, in: parent) }
            if candidates.isEmpty { return [] }
        }
        return candidates
    }

    private static func expandingHome(in pattern: String, homeDirectory: URL) -> String {
        guard pattern == homePrefix || pattern.hasPrefix(homePrefix + String(pathSeparator)) else { return pattern }
        return homeDirectory.path + pattern.dropFirst(homePrefix.count)
    }

    private static func matches(of component: String, in parent: URL) -> [URL] {
        guard component.contains(where: { character in wildcardCharacters.contains(character) }) else {
            return [parent.appendingPathComponent(component, isDirectory: true)]
        }
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: parent.path) else { return [] }
        return entries
            .sorted()
            .filter { entryName in fnmatch(component, entryName, FNM_PERIOD) == 0 }
            .map { entryName in parent.appendingPathComponent(entryName, isDirectory: true) }
            .filter { entryURL in isDirectory(entryURL) }
    }

    private static func isDirectory(_ entryURL: URL) -> Bool {
        var isDirectoryFlag: ObjCBool = false
        return FileManager.default.fileExists(atPath: entryURL.path, isDirectory: &isDirectoryFlag) && isDirectoryFlag.boolValue
    }
}
