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

    @Test(arguments: ["clear", "resume"])
    func aSessionEndOfARecordWithNoProcessRemovesIt(reason: String) throws {
        let sandbox = try Sandbox()
        var record = RecordFixtures.enrolled(visible: true)
        record.removeValue(forKey: "pid")
        try sandbox.writeRecord(record)
        try sandbox.hook(RecordFixtures.hookPayload("SessionEnd", extra: ["reason": reason]))

        #expect(!sandbox.exists(sandbox.recordURL(RecordFixtures.sessionId)))
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

    /// A Claude started from another Claude's Bash tool (`claude -p --resume`, say) runs its hooks with
    /// the parent Claude two levels up. The parent's pet stays the parent's.
    @Test(arguments: ["resume", "clear"])
    func aClaudeStartedFromAnotherClaudesShellNeverTakesTheParentsPet(source: String) throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "parent", extra: ["label": "Parent"]))
        try sandbox.hook(RecordFixtures.hookPayload("SessionStart", sessionId: "child", extra: ["source": source]), throughShell: true)

        #expect(!sandbox.exists(sandbox.recordURL("child")))
        #expect(sandbox.record("parent")?["label"] as? String == "Parent")
        #expect(sandbox.hookLogLines().isEmpty)
    }

    @Test func aChildWhoseSessionFileNamesItselfNeverTakesTheParentsPet() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "parent", extra: ["label": "Parent"]))
        try sandbox.writeClaudeSession(processIdentifier: Int32(deadProcessIdentifier), sessionId: "child")
        try sandbox.hook(RecordFixtures.hookPayload("SessionStart", sessionId: "child", extra: ["source": "resume"]))

        #expect(!sandbox.exists(sandbox.recordURL("child")))
        #expect(sandbox.exists(sandbox.recordURL("parent")))
    }

    /// Claude Code's session file names the process, however far up the hook it sits.
    @Test func theSessionFileForTheNewIdNamesTheProcessThatTakesThePet() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "before", extra: ["label": "Mine"]))
        try sandbox.writeClaudeSession(processIdentifier: getpid(), sessionId: "after")
        try sandbox.hook(RecordFixtures.hookPayload("SessionStart", sessionId: "after", extra: ["source": "clear"]), throughShell: true)

        #expect(!sandbox.exists(sandbox.recordURL("before")))
        #expect(sandbox.record("after")?["label"] as? String == "Mine")
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

    private func idleLine(teammate: String, envelope: String? = nil, timestamp: String? = nil) -> String {
        let stamp = timestamp.map { value in ",\\\"timestamp\\\":\\\"\(value)\\\"" } ?? ""
        let payload = "{\\\"type\\\":\\\"idle_notification\\\",\\\"from\\\":\\\"\(teammate)\\\"\(stamp),\\\"idleReason\\\":\\\"available\\\"}"
        let opening = envelope.map { name in "<teammate-message teammate_id=\\\"\(name)\\\">\\n" } ?? ""
        return "{\"type\":\"user\",\"message\":{\"content\":\"\(opening)\(payload)\"}}\n"
    }

    /// The lead spawned a second `fixer` after the first one went idle. The first one's notice says
    /// nothing about the second, which is still working.
    @Test func anEarlierTeammateOfTheSameNameGoingIdleLeavesANewOneWorking() throws {
        let sandbox = try Sandbox()
        let transcript = sandbox.home.appendingPathComponent("transcript.jsonl")
        let now = Date().timeIntervalSince1970
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let wentIdle = formatter.string(from: Date(timeIntervalSince1970: now - 60))
        try idleLine(teammate: "fixer", envelope: "fixer", timestamp: wentIdle)
            .write(to: transcript, atomically: true, encoding: .utf8)
        let spawnedBefore = now - 120
        let spawnedAfter = now - 10
        try sandbox.writeRecord(RecordFixtures.enrolled(activeSubagents: [
            RecordFixtures.trackedSubagent("afixer-d035f68f1e116378", startedAt: spawnedBefore),
            RecordFixtures.trackedSubagent("afixer-1111222233334444", startedAt: spawnedAfter)
        ]))
        try sandbox.hook(RecordFixtures.hookPayload("Stop", extra: ["transcript_path": transcript.path]))

        #expect(sandbox.activeSubagentIds(RecordFixtures.sessionId) == ["afixer-1111222233334444"])
    }

    /// Only a real teammate message counts: a payload quoted with no envelope (a Read of a fixture), or
    /// one whose envelope names somebody else, finishes nobody.
    @Test(arguments: [nil, "reviewer"] as [String?])
    func aQuotedIdleNotificationFinishesNobody(envelope: String?) throws {
        let sandbox = try Sandbox()
        let transcript = sandbox.home.appendingPathComponent("transcript.jsonl")
        try idleLine(teammate: "fixer", envelope: envelope).write(to: transcript, atomically: true, encoding: .utf8)
        try sandbox.writeRecord(RecordFixtures.enrolled(activeSubagents: [
            RecordFixtures.trackedSubagent("afixer-d035f68f1e116378")
        ]))
        try sandbox.hook(RecordFixtures.hookPayload("Stop", extra: ["transcript_path": transcript.path]))

        #expect(sandbox.activeSubagentIds(RecordFixtures.sessionId) == ["afixer-d035f68f1e116378"])
    }
}
