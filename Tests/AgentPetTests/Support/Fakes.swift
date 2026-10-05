import Foundation
@testable import AgentPetCore

final class RecordingTmux: TmuxCommandRunning {
    var calls: [[String]] = []
    var capturedOutputBySubcommand: [TmuxSubcommand: String] = [:]

    func run(subcommand: TmuxSubcommand, arguments: [String]) {
        calls.append([subcommand.rawValue] + arguments)
    }

    func capture(subcommand: TmuxSubcommand, arguments: [String]) -> String? {
        calls.append([subcommand.rawValue] + arguments)
        return capturedOutputBySubcommand[subcommand]
    }
}

final class RecordingTerminals: TerminalControlling {
    var runningTerminals: Set<TerminalBundleIdentifier> = []
    var itermScriptOutput: String?
    var itermScripts: [String] = []
    var activatedTerminals: [TerminalBundleIdentifier] = []

    func isRunning(_ terminal: TerminalBundleIdentifier) -> Bool {
        runningTerminals.contains(terminal)
    }

    func runItermScript(_ script: String) -> String? {
        itermScripts.append(script)
        return itermScriptOutput
    }

    func activate(_ terminal: TerminalBundleIdentifier) -> Bool {
        activatedTerminals.append(terminal)
        return true
    }
}

final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-pet-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func makeDirectory(_ relativePath: String) throws -> URL {
        let directory = url.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func write(_ contents: String, to relativePath: String) throws -> URL {
        let fileURL = url.appendingPathComponent(relativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
