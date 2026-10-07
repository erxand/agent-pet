import Foundation

struct CommandRun {
    let exitStatus: Int32
    let standardOutput: String
    let standardError: String
}

enum SandboxFailure: Error {
    case binaryNotFound
    case timedOut([String])
}

final class Sandbox {
    static let binaryOverrideVariable = "AGENT_PET_TEST_BINARY"
    private static let binaryName = "agent-pet"
    private static let commandTimeoutInSeconds: TimeInterval = 60
    private static let tmuxLogFileName = "tmux.log"
    private static let tmuxFieldSeparator = "\u{1F}"

    let home: URL
    let stubDirectory: URL
    private let fileManager = FileManager.default

    init() throws {
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("agent-pet-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        home = base.appendingPathComponent("home", isDirectory: true)
        stubDirectory = base.appendingPathComponent("stubs", isDirectory: true)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: stubDirectory, withIntermediateDirectories: true)
        try writeTmuxStub()
        try fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: spritesDirectory, withIntermediateDirectories: true)
        try "\(getpid())\n".write(to: stateDirectory.appendingPathComponent("daemon.pid"), atomically: true, encoding: .utf8)
    }

    deinit {
        try? fileManager.removeItem(at: home.deletingLastPathComponent())
    }

    var stateDirectory: URL { home.appendingPathComponent(".agent-pet", isDirectory: true) }
    var sessionsDirectory: URL { stateDirectory.appendingPathComponent("sessions", isDirectory: true) }
    var spritesDirectory: URL { stateDirectory.appendingPathComponent("sprites", isDirectory: true) }
    var hookLog: URL { stateDirectory.appendingPathComponent("hooks.log") }
    var daemonLog: URL { stateDirectory.appendingPathComponent("daemon.log") }
    var claudeSessionsDirectory: URL { home.appendingPathComponent(".claude/sessions", isDirectory: true) }
    var tmuxStub: URL { stubDirectory.appendingPathComponent("tmux") }

    func recordURL(_ sessionId: String) -> URL {
        sessionsDirectory.appendingPathComponent("\(sessionId).json")
    }

    func lockURL(_ sessionId: String) -> URL {
        sessionsDirectory.appendingPathComponent("\(sessionId).lock")
    }

    func exists(_ fileURL: URL) -> Bool {
        fileManager.fileExists(atPath: fileURL.path)
    }

    @discardableResult
    func run(
        _ arguments: [String],
        standardInput: String? = nil,
        environment extraEnvironment: [String: String] = [:],
        throughShell: Bool = false
    ) throws -> CommandRun {
        let process = Process()
        if throughShell {
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "\"$0\" \"$@\"; exit $?", try Sandbox.binaryURL().path] + arguments
        } else {
            process.executableURL = try Sandbox.binaryURL()
            process.arguments = arguments
        }
        var environment = [
            "HOME": home.path,
            "CFFIXED_USER_HOME": home.path,
            "PATH": "/usr/bin:/bin",
            "TMUX_EXECUTABLE": tmuxStub.path
        ]
        environment.merge(extraEnvironment) { _, extraValue in extraValue }
        process.environment = environment
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        if let standardInput {
            inputPipe.fileHandleForWriting.write(Data(standardInput.utf8))
        }
        try inputPipe.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(Sandbox.commandTimeoutInSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            process.terminate()
            throw SandboxFailure.timedOut(arguments)
        }
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        return CommandRun(
            exitStatus: process.terminationStatus,
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData, as: UTF8.self)
        )
    }

    @discardableResult
    func hook(_ payload: [String: Any], environment: [String: String] = [:], throughShell: Bool = false) throws -> CommandRun {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try run(
            ["hook"],
            standardInput: String(decoding: data, as: UTF8.self),
            environment: environment,
            throughShell: throughShell
        )
    }

    func writeRecord(_ record: [String: Any]) throws {
        guard let sessionId = record["sessionId"] as? String else { return }
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        try data.write(to: recordURL(sessionId))
    }

    func record(_ sessionId: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: recordURL(sessionId)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    func activeSubagentIds(_ sessionId: String) -> [String] {
        let entries = record(sessionId)?["activeSubagents"] as? [[String: Any]] ?? []
        return entries.compactMap { entry in entry["id"] as? String }
    }

    func hookLogLines() -> [String] {
        guard let contents = try? String(contentsOf: hookLog, encoding: .utf8) else { return [] }
        return contents.split(separator: "\n").map { line in String(line) }
    }

    func writeClaudeSession(processIdentifier: Int32, sessionId: String, name: String? = nil, cwd: String? = nil, tmux: String? = nil) throws {
        try fileManager.createDirectory(at: claudeSessionsDirectory, withIntermediateDirectories: true)
        var payload: [String: Any] = ["pid": Int(processIdentifier), "sessionId": sessionId]
        if let name { payload["name"] = name }
        if let cwd { payload["cwd"] = cwd }
        if let tmux { payload["tmux"] = tmux }
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: claudeSessionsDirectory.appendingPathComponent("\(processIdentifier).json"))
    }

    func installPack(_ packName: String) throws {
        let source = Sandbox.packageRoot.appendingPathComponent("sprites/\(packName)", isDirectory: true)
        try fileManager.copyItem(at: source, to: spritesDirectory.appendingPathComponent(packName, isDirectory: true))
    }

    func setTmuxOutput(subcommand: String, output: String) throws {
        try output.write(to: stubDirectory.appendingPathComponent("\(subcommand).out"), atomically: true, encoding: .utf8)
    }

    func tmuxCalls() -> [[String]] {
        let logURL = stubDirectory.appendingPathComponent(Sandbox.tmuxLogFileName)
        guard let contents = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
        return contents.split(separator: "\n").map { line in
            line.components(separatedBy: Sandbox.tmuxFieldSeparator)
        }
    }

    private func writeTmuxStub() throws {
        let logPath = stubDirectory.appendingPathComponent(Sandbox.tmuxLogFileName).path
        let script = """
        #!/bin/sh
        out=""
        for argument in "$@"; do
            if [ -z "$out" ]; then out="$argument"; else out="$out$(printf '\\037')$argument"; fi
        done
        printf '%s\\n' "$out" >> '\(logPath)'
        if [ -f '\(stubDirectory.path)'/"$1".out ]; then cat '\(stubDirectory.path)'/"$1".out; fi
        exit 0
        """
        try script.write(to: tmuxStub, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmuxStub.path)
    }

    static let packageRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func binaryURL() throws -> URL {
        if let override = ProcessInfo.processInfo.environment[binaryOverrideVariable], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        var candidates: [URL] = []
        for argument in CommandLine.arguments {
            guard let bundleRange = argument.range(of: ".xctest") else { continue }
            let bundlePath = String(argument[argument.startIndex..<bundleRange.upperBound])
            candidates.append(URL(fileURLWithPath: bundlePath).deletingLastPathComponent().appendingPathComponent(binaryName))
        }
        let buildDirectory = packageRoot.appendingPathComponent(".build", isDirectory: true)
        candidates.append(buildDirectory.appendingPathComponent("out/Products/Debug/\(binaryName)"))
        candidates.append(buildDirectory.appendingPathComponent("debug/\(binaryName)"))
        guard let found = candidates.first(where: { candidate in
            FileManager.default.isExecutableFile(atPath: candidate.path)
        }) else {
            throw SandboxFailure.binaryNotFound
        }
        return found
    }
}
