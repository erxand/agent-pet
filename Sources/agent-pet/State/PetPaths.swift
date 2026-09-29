import Foundation

enum PetPaths {
    static let sessionRecordFileExtension = "json"

    private static let stateDirectoryName = ".agent-pet"
    private static let sessionsDirectoryName = "sessions"
    private static let spritesDirectoryName = "sprites"
    private static let claudeDirectoryName = ".claude"
    private static let claudeSessionsDirectoryName = "sessions"
    private static let daemonProcessIdentifierFileName = "daemon.pid"
    private static let daemonLogFileName = "daemon.log"

    static var homeDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    static var stateDirectory: URL {
        homeDirectory.appendingPathComponent(stateDirectoryName, isDirectory: true)
    }

    static var sessionsDirectory: URL {
        stateDirectory.appendingPathComponent(sessionsDirectoryName, isDirectory: true)
    }

    static var spritesDirectory: URL {
        stateDirectory.appendingPathComponent(spritesDirectoryName, isDirectory: true)
    }

    static var claudeSessionsDirectory: URL {
        homeDirectory
            .appendingPathComponent(claudeDirectoryName, isDirectory: true)
            .appendingPathComponent(claudeSessionsDirectoryName, isDirectory: true)
    }

    static var daemonProcessIdentifierFile: URL {
        stateDirectory.appendingPathComponent(daemonProcessIdentifierFileName, isDirectory: false)
    }

    static var daemonLogFile: URL {
        stateDirectory.appendingPathComponent(daemonLogFileName, isDirectory: false)
    }

    static func createStateDirectoriesIfNeeded() {
        let fileManager = FileManager.default
        for directory in [stateDirectory, sessionsDirectory, spritesDirectory] {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
