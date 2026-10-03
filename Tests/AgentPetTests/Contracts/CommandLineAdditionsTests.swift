import Foundation
import Testing

@Suite("command line additions")
struct CommandLineAdditionsTests {
    private let sessionId = RecordFixtures.sessionId

    @Test func onFromAnyShellStoresTheLabelAndFocusTarget() throws {
        let sandbox = try Sandbox()
        let run = try sandbox.run(["on", "--session", sessionId, "--label", "Dev System", "--focus-target", "termie:pane:42"])

        #expect(run.exitStatus == 0)
        #expect(run.standardOutput.hasPrefix("pet on for Dev System, sprite "))
        let record = try #require(sandbox.record(sessionId))
        #expect(record["label"] as? String == "Dev System")
        #expect(record["focusTarget"] as? String == "termie:pane:42")
        #expect(record["tmuxTarget"] == nil)
    }

    @Test func rerunningOnUpdatesInPlace() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        try sandbox.installPack("nimbus")
        try sandbox.run(["on", "--session", sessionId, "--label", "first", "--focus-target", "pane-1"])
        let firstSprite = sandbox.record(sessionId)?["sprite"] as? String
        try sandbox.hook(RecordFixtures.hookPayload("SubagentStart", extra: ["agent_id": "agent-one"]))
        try sandbox.hook(RecordFixtures.hookPayload("SubagentStart", extra: ["description": "no id"]))

        try sandbox.run(["on", "--session", sessionId, "--label", "second"])
        let record = try #require(sandbox.record(sessionId))
        #expect(record["label"] as? String == "second")
        #expect(record["focusTarget"] as? String == "pane-1")
        #expect(record["sprite"] as? String == firstSprite)
        #expect(sandbox.activeSubagentIds(sessionId) == ["agent-one", "unknown-1"])

        try sandbox.run(["on", "--session", sessionId, "--focus-target", "pane-2"])
        #expect(sandbox.record(sessionId)?["focusTarget"] as? String == "pane-2")
    }

    @Test func showAlsoTakesTheFocusTarget() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled())
        try sandbox.run(["show", "--session", sessionId, "--focus-target", "pane-7"])

        #expect(sandbox.record(sessionId)?["focusTarget"] as? String == "pane-7")
    }

    @Test func statusJsonListsEverySession() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(visible: true, extra: [
            "label": "json label",
            "sprite": "golem",
            "accent": "green",
            "focusTarget": "pane-3",
            "activeSubagents": [RecordFixtures.trackedSubagent("agent-one")]
        ]))
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "dead-session", extra: ["pid": 999_999]))
        let run = try sandbox.run(["status", "--json"])
        #expect(run.exitStatus == 0)

        let report = try #require(try JSONSerialization.jsonObject(with: Data(run.standardOutput.utf8)) as? [String: Any])
        #expect(report["daemonPid"] as? Int == Int(getpid()))
        let sessions = try #require(report["sessions"] as? [[String: Any]])
        let live = try #require(sessions.first { entry in entry["sessionId"] as? String == sessionId })
        #expect(live["group"] as? String == sessionId)
        #expect(live["label"] as? String == "json label")
        #expect(live["sprite"] as? String == "golem")
        #expect(live["accent"] as? String == "green")
        #expect(live["agent"] as? String == "claude-code")
        #expect(live["enabled"] as? Bool == true)
        #expect(live["visible"] as? Bool == true)
        #expect(live["mood"] as? String == "ready")
        #expect(live["activeSubagents"] as? Int == 1)
        #expect(live["alive"] as? Bool == true)
        #expect(live["pid"] as? Int == Int(getpid()))
        #expect(live["focusTarget"] as? String == "pane-3")
        let dead = try #require(sessions.first { entry in entry["sessionId"] as? String == "dead-session" })
        #expect(dead["alive"] as? Bool == false)
        #expect(dead["focusTarget"] is NSNull)
    }

    @Test func statusJsonSaysNullWhenNoDaemonRuns() throws {
        let sandbox = try Sandbox()
        try FileManager.default.removeItem(at: sandbox.stateDirectory.appendingPathComponent("daemon.pid"))
        let run = try sandbox.run(["status", "--json"])

        let report = try #require(try JSONSerialization.jsonObject(with: Data(run.standardOutput.utf8)) as? [String: Any])
        #expect(report["daemonPid"] is NSNull)
        #expect((report["sessions"] as? [Any])?.isEmpty == true)
    }
}
