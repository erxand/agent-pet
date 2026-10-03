import Foundation
import Testing

@Suite("behavior chosen by a config file")
struct ConfiguredBehaviorTests {
    private let sessionId = RecordFixtures.sessionId

    private func writeConfig(_ sandbox: Sandbox, _ json: String) throws {
        try json.write(to: sandbox.stateDirectory.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
    }

    @Test func anEmptyConfigBehavesExactlyLikeNoConfig() throws {
        let withoutConfig = try Sandbox()
        let withEmptyConfig = try Sandbox()
        try writeConfig(withEmptyConfig, "{}")
        var outputs: [String] = []
        for sandbox in [withoutConfig, withEmptyConfig] {
            try sandbox.installPack("golem")
            let run = try sandbox.run(["on", "--session", sessionId, "--tmux", "work:@3.%7"])
            outputs.append(run.standardOutput)
            #expect(sandbox.tmuxCalls() == [
                ["send-keys", "-t", "work:@3.%7", "-l", "/color green"],
                ["send-keys", "-t", "work:@3.%7", "Enter"]
            ])
        }
        #expect(outputs[0] == outputs[1])
    }

    @Test func colorSyncNoneTypesNothing() throws {
        let sandbox = try Sandbox()
        try writeConfig(sandbox, #"{"colorSync":"none"}"#)
        try sandbox.run(["on", "--session", sessionId, "--tmux", "work:@3.%7"])
        try sandbox.run(["off", "--session", sessionId])

        #expect(sandbox.tmuxCalls().isEmpty)
    }

    @Test func extraSessionDirectoriesFeedLabelsAndLiveness() throws {
        let sandbox = try Sandbox()
        let profileSessions = sandbox.home.appendingPathComponent(".claude-reina/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: profileSessions, withIntermediateDirectories: true)
        let json = #"{"pid":\#(getpid()),"sessionId":"\#(sessionId)","name":"reina site"}"#
        try json.write(to: profileSessions.appendingPathComponent("\(getpid()).json"), atomically: true, encoding: .utf8)
        try sandbox.writeRecord(RecordFixtures.enrolled(extra: ["pid": NSNull(), "updatedAt": Date().timeIntervalSince1970 - 120]))

        let defaultStatus = try sandbox.run(["status"]).standardOutput
        #expect(defaultStatus.contains("session"))
        #expect(defaultStatus.split(separator: "\n")[1].hasSuffix("no"))

        try writeConfig(sandbox, #"{"sessionDirectories":["~/.claude/sessions","~/.claude-*/sessions"]}"#)
        let configuredStatus = try sandbox.run(["status"]).standardOutput
        let row = configuredStatus.split(separator: "\n")[1]
        #expect(row.contains("reina site"))
        #expect(row.hasSuffix("yes"))
    }

    @Test func agentPetConfigPointsAtAnotherFile() throws {
        let sandbox = try Sandbox()
        let elsewhere = sandbox.home.appendingPathComponent("elsewhere.json")
        try #"{"colorSync":"none"}"#.write(to: elsewhere, atomically: true, encoding: .utf8)
        try sandbox.run(["on", "--session", sessionId, "--tmux", "work:@3.%7"], environment: ["AGENT_PET_CONFIG": elsewhere.path])

        #expect(sandbox.tmuxCalls().isEmpty)
    }

    @Test func theCommandFocuserRunsTheConfiguredCommandAndNoTmux() throws {
        let sandbox = try Sandbox()
        let output = sandbox.home.appendingPathComponent("focus.out")
        let script = sandbox.home.appendingPathComponent("focus.sh")
        try """
        #!/bin/sh
        echo "$AGENT_PET_SESSION_ID $AGENT_PET_FOCUS_TARGET $AGENT_PET_AGENT" > '\(output.path)'
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        try writeConfig(sandbox, #"{"focuser":{"kind":"command","command":["\#(script.path)"]}}"#)

        let missing = try sandbox.run(["focus", "--session", sessionId])
        #expect(missing.exitStatus == 2)
        #expect(missing.standardError.contains("no record for session \(sessionId)"))

        try sandbox.writeRecord(RecordFixtures.enrolled(extra: ["tmuxTarget": "work:@3.%7", "focusTarget": "pane-9"]))
        let run = try sandbox.run(["focus", "--session", sessionId])
        #expect(run.exitStatus == 0)
        #expect(try String(contentsOf: output, encoding: .utf8) == "\(sessionId) pane-9 claude-code\n")
        #expect(sandbox.tmuxCalls().isEmpty)
    }
}
