import Foundation
import Testing

@Suite("a pet's whole life: handed over, cleared, finished")
struct PetLifecycleTests {
    private let paneTarget = "termie:42"
    private let deadProcessIdentifier = 999_999

    private func enrolledOnPane(_ extra: [String: Any] = [:], visible: Bool = false) -> [String: Any] {
        var fields: [String: Any] = ["focusTarget": paneTarget]
        fields.merge(extra) { _, extraValue in extraValue }
        return RecordFixtures.enrolled(visible: visible, extra: fields)
    }

    @Test func anIdlePromptEndsAStuckTurnWithoutShowingAnything() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(extra: ["busy": true]))
        try sandbox.hook(RecordFixtures.hookPayload("Notification", extra: ["notification_type": "idle_prompt"]))

        let record = try #require(sandbox.record(RecordFixtures.sessionId))
        #expect(record["busy"] == nil)
        #expect(record["visible"] as? Bool == false)
    }

    @Test(arguments: ["worker_permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input"])
    func everyQuestionForHimShowsNeedsInput(notificationType: String) throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled())
        try sandbox.hook(RecordFixtures.hookPayload("Notification", extra: ["notification_type": notificationType]))

        let record = try #require(sandbox.record(RecordFixtures.sessionId))
        #expect(record["visible"] as? Bool == true)
        #expect(record["mood"] as? String == "needsInput")
    }

    @Test func aSubagentsToolCallLeavesAnotherSubagentsQuestionUp() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(visible: true, extra: ["mood": "needsInput"]))
        try sandbox.hook(RecordFixtures.hookPayload("PreToolUse", extra: ["agent_id": "agent-two", "tool_name": "Bash"]))

        let record = try #require(sandbox.record(RecordFixtures.sessionId))
        #expect(record["visible"] as? Bool == true)
        #expect(record["busy"] as? Bool == true)

        try sandbox.hook(RecordFixtures.hookPayload("PreToolUse", extra: ["tool_name": "Bash"]))
        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == false)
    }

    @Test func aSubagentsToolCallStillHidesAReadyPet() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(visible: true))
        try sandbox.hook(RecordFixtures.hookPayload("PreToolUse", extra: ["agent_id": "agent-two", "tool_name": "Bash"]))

        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == false)
    }

    @Test(arguments: ["clear", "resume"])
    func aSessionEndThatContinuesInTheSameProcessKeepsTheRecordHidden(reason: String) throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(visible: true, extra: ["busy": true]))
        try sandbox.hook(RecordFixtures.hookPayload("SessionEnd", extra: ["reason": reason]))

        let record = try #require(sandbox.record(RecordFixtures.sessionId))
        #expect(record["visible"] as? Bool == false)
        #expect(record["busy"] == nil)
        #expect(sandbox.hookLogLines().last?.hasSuffix("visible=false agents=0 reason=\(reason)") == true)
    }

    @Test(arguments: ["prompt_input_exit", "logout", "other"])
    func aSessionEndThatEndsTheProcessRemovesTheRecord(reason: String) throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled())
        try sandbox.hook(RecordFixtures.hookPayload("SessionEnd", extra: ["reason": reason]))

        #expect(!sandbox.exists(sandbox.recordURL(RecordFixtures.sessionId)))
    }

    @Test func clearHandsThePetToTheNewSessionIdOfTheSameProcess() throws {
        let sandbox = try Sandbox()
        let newSessionId = "99999999-8888-7777-6666-555555555555"
        try sandbox.writeRecord(RecordFixtures.enrolled(visible: true, activeSubagents: [RecordFixtures.trackedSubagent("agent-one")], extra: [
            "label": "Dev System", "sprite": "claude", "group": "win:abc", "focusTarget": paneTarget,
            "busy": true, "transcriptPath": "/tmp/old.jsonl", "transcriptScanOffset": 99
        ]))
        try sandbox.hook(RecordFixtures.hookPayload("SessionEnd", extra: ["reason": "clear"]))
        try sandbox.hook(RecordFixtures.hookPayload("SessionStart", sessionId: newSessionId, extra: ["source": "clear"]))

        #expect(!sandbox.exists(sandbox.recordURL(RecordFixtures.sessionId)))
        let record = try #require(sandbox.record(newSessionId))
        #expect(record["label"] as? String == "Dev System")
        #expect(record["group"] as? String == "win:abc")
        #expect(record["focusTarget"] as? String == paneTarget)
        #expect(record["pid"] as? Int == Int(getpid()))
        #expect(record["visible"] as? Bool == false)
        #expect(record["busy"] == nil)
        #expect(record["transcriptPath"] == nil)
        #expect(sandbox.activeSubagentIds(newSessionId).isEmpty)
        #expect(sandbox.hookLogLines().last?.hasSuffix("SessionStart 99999999 - visible=false agents=0 source=clear") == true)

        try sandbox.hook(RecordFixtures.hookPayload("Stop", sessionId: newSessionId))
        #expect(sandbox.record(newSessionId)?["visible"] as? Bool == true)
    }

    @Test func aStartupOrAnotherProcessesPetIsNeverTakenOver() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "elsewhere", extra: ["pid": deadProcessIdentifier]))
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "mine"))
        try sandbox.hook(RecordFixtures.hookPayload("SessionStart", sessionId: "fresh", extra: ["source": "startup"]))
        #expect(!sandbox.exists(sandbox.recordURL("fresh")))
        #expect(sandbox.exists(sandbox.recordURL("mine")))

        try FileManager.default.removeItem(at: sandbox.recordURL("mine"))
        try sandbox.hook(RecordFixtures.hookPayload("SessionStart", sessionId: "fresh", extra: ["source": "clear"]))
        #expect(!sandbox.exists(sandbox.recordURL("fresh")))
        #expect(sandbox.exists(sandbox.recordURL("elsewhere")))
        #expect(sandbox.hookLogLines().isEmpty)
    }

    @Test func removeByProcessTakesEveryRecordOfThatProcess() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "after-clear"))
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "other", extra: ["pid": deadProcessIdentifier]))
        try sandbox.run(["remove", "--pid", String(getpid())])

        #expect(!sandbox.exists(sandbox.recordURL("after-clear")))
        #expect(sandbox.exists(sandbox.recordURL("other")))
    }

    @Test func hideByFocusTargetTakesThePanesPetDown() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(enrolledOnPane(visible: true))
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "other", visible: true))
        let run = try sandbox.run(["hide", "--focus-target", paneTarget])

        #expect(run.exitStatus == 0)
        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == false)
        #expect(sandbox.record("other")?["visible"] as? Bool == true)
    }

    @Test func removeByFocusTargetTakesThePanesPet() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(enrolledOnPane())
        try sandbox.run(["remove", "--focus-target", paneTarget])

        #expect(!sandbox.exists(sandbox.recordURL(RecordFixtures.sessionId)))
    }

    @Test func rerunningOnKeepsAPetThatIsUp() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(visible: true))
        try sandbox.run(["on", "--session", RecordFixtures.sessionId, "--label", "renamed", "--no-color-sync"])

        let record = try #require(sandbox.record(RecordFixtures.sessionId))
        #expect(record["visible"] as? Bool == true)
        #expect(record["label"] as? String == "renamed")
    }

    @Test func anIdleTeammateNoLongerHoldsTheLeadsPetDown() throws {
        let sandbox = try Sandbox()
        let transcript = sandbox.home.appendingPathComponent("transcript.jsonl")
        let idleLine = "{\"type\":\"user\",\"message\":{\"content\":\"<teammate-message teammate_id=\\\"fixer-7\\\">\\n{\\\"type\\\":\\\"idle_notification\\\",\\\"from\\\":\\\"fixer-7\\\",\\\"idleReason\\\":\\\"failed\\\"}\"}}\n"
        try idleLine.write(to: transcript, atomically: true, encoding: .utf8)
        try sandbox.writeRecord(RecordFixtures.enrolled(activeSubagents: [
            RecordFixtures.trackedSubagent("afixer-7-d035f68f1e116378"),
            RecordFixtures.trackedSubagent("afixer-70-d035f68f1e116378")
        ]))
        try sandbox.hook(RecordFixtures.hookPayload("Stop", extra: ["transcript_path": transcript.path]))

        #expect(sandbox.activeSubagentIds(RecordFixtures.sessionId) == ["afixer-70-d035f68f1e116378"])
        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == false)
    }
}
