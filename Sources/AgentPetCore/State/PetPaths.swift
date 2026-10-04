import Foundation

package enum PetPaths {
    package static let sessionRecordFileExtension = "json"
    package static let sessionLockFileExtension = "lock"

    private static let stateDirectoryName = ".agent-pet"
    private static let sessionsDirectoryName = "sessions"
    private static let spritesDirectoryName = "sprites"
    private static let claudeDirectoryName = ".claude"
    private static let claudeSessionsDirectoryName = "sessions"
    private static let daemonProcessIdentifierFileName = "daemon.pid"
    private static let daemonLogFileName = "daemon.log"
    private static let hookLogFileName = "hooks.log"

    package static var homeDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    package static var stateDirectory: URL {
        homeDirectory.appendingPathComponent(stateDirectoryName, isDirectory: true)
    }

    package static var sessionsDirectory: URL {
        stateDirectory.appendingPathComponent(sessionsDirectoryName, isDirectory: true)
    }

    package static var spritesDirectory: URL {
        stateDirectory.appendingPathComponent(spritesDirectoryName, isDirectory: true)
    }

    package static var claudeSessionsDirectory: URL {
        homeDirectory
            .appendingPathComponent(claudeDirectoryName, isDirectory: true)
            .appendingPathComponent(claudeSessionsDirectoryName, isDirectory: true)
    }

    package static var daemonProcessIdentifierFile: URL {
        stateDirectory.appendingPathComponent(daemonProcessIdentifierFileName, isDirectory: false)
    }

    package static var daemonLogFile: URL {
        stateDirectory.appendingPathComponent(daemonLogFileName, isDirectory: false)
    }

    package static var hookLogFile: URL {
        stateDirectory.appendingPathComponent(hookLogFileName, isDirectory: false)
    }

    package static func createStateDirectoriesIfNeeded() {
        let fileManager = FileManager.default
        for directory in [stateDirectory, sessionsDirectory, spritesDirectory] {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
