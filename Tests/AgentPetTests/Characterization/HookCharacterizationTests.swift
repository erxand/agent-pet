import Foundation
import Testing

@Suite("hook events with no config file")
struct HookCharacterizationTests {
    @Test func stopWithNoSubagentsShowsTheReadyPetWithTheFirstLineOfTheLastMessage() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(extra: ["mood": "needsInput"]))
        let longFirstLine = String(repeating: "x", count: 100)
        let run = try sandbox.hook(RecordFixtures.hookPayload(
            "Stop",
            extra: ["last_assistant_message": "  \(longFirstLine)  \nsecond line"]
        ))

        #expect(run.exitStatus == 0)
        #expect(run.standardOutput.isEmpty)
        let record = try #require(sandbox.record(RecordFixtures.sessionId))
        #expect(record["visible"] as? Bool == true)
        #expect(record["mood"] as? String == "ready")
        #expect(record["message"] as? String == String(repeating: "x", count: 80))
        let line = try #require(sandbox.hookLogLines().last)
        #expect(line.hasSuffix("Stop \(RecordFixtures.shortSessionId) - visible=true agents=0"))
        #expect(!sandbox.exists(sandbox.daemonLog))
    }

    @Test func stopWithARunningSubagentStaysHidden() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(
            visible: true,
            activeSubagents: [RecordFixtures.trackedSubagent("agent-one")]
        ))
        try sandbox.hook(RecordFixtures.hookPayload("Stop"))

        let record = try #require(sandbox.record(RecordFixtures.sessionId))
        #expect(record["visible"] as? Bool == false)
        #expect(sandbox.hookLogLines().last?.hasSuffix("visible=false agents=1") == true)
    }

    @Test func stopOnADisabledRecordShowsNothing() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(enabled: false))
        try sandbox.hook(RecordFixtures.hookPayload("Stop"))

        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == false)
    }

    @Test func subagentStartTracksAndHidesAndSubagentStopForgets() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(visible: true))

        try sandbox.hook(RecordFixtures.hookPayload("SubagentStart", extra: ["agent_id": "agent-one"]))
        #expect(sandbox.activeSubagentIds(RecordFixtures.sessionId) == ["agent-one"])
        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == false)
        #expect(sandbox.hookLogLines().last?.hasSuffix(
            "SubagentStart \(RecordFixtures.shortSessionId) agent-one visible=false agents=1"
        ) == true)

        try sandbox.hook(RecordFixtures.hookPayload("SubagentStop", extra: ["agent_id": "agent-one"]))
        #expect(sandbox.activeSubagentIds(RecordFixtures.sessionId).isEmpty)
        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == false)
    }

    @Test func aRepeatedSubagentStartWithTheSameIdIsCountedOnce() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled())
        let payload = RecordFixtures.hookPayload("SubagentStart", extra: ["agent_id": "agent-one"])
        try sandbox.hook(payload)
        try sandbox.hook(payload)

        #expect(sandbox.activeSubagentIds(RecordFixtures.sessionId) == ["agent-one"])
    }

    @Test func subagentEventsWithoutAnAgentIdDegradeToACounter() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled())
        try sandbox.hook(RecordFixtures.hookPayload("SubagentStart", extra: ["description": "first"]))
        try sandbox.hook(RecordFixtures.hookPayload("SubagentStart", extra: ["description": "second"]))
        #expect(sandbox.activeSubagentIds(RecordFixtures.sessionId) == ["unknown-1", "unknown-2"])

        try sandbox.hook(RecordFixtures.hookPayload("SubagentStop", extra: ["description": "second"]))
        #expect(sandbox.activeSubagentIds(RecordFixtures.sessionId) == ["unknown-1"])
    }

    @Test func aPermissionPromptShowsNeedsInputWhateverTheSubagentsAreDoing() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(activeSubagents: [RecordFixtures.trackedSubagent("agent-one")]))
        try sandbox.hook(RecordFixtures.hookPayload("Notification", extra: ["notification_type": "permission_prompt"]))

        let record = try #require(sandbox.record(RecordFixtures.sessionId))
        #expect(record["visible"] as? Bool == true)
        #expect(record["mood"] as? String == "needsInput")
    }

    @Test func anOtherNotificationTypeChangesNothing() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled())
        try sandbox.hook(RecordFixtures.hookPayload("Notification", extra: ["notification_type": "idle_prompt"]))

        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == false)
        #expect(sandbox.hookLogLines().last?.hasSuffix("Notification \(RecordFixtures.shortSessionId) - visible=false agents=0") == true)
    }

    @Test func userPromptSubmitAndPreToolUseHideAndLeaveSubagentsAlone() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(
            visible: true,
            activeSubagents: [RecordFixtures.trackedSubagent("agent-one")]
        ))
        try sandbox.hook(RecordFixtures.hookPayload("UserPromptSubmit"))
        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == false)
        #expect(sandbox.activeSubagentIds(RecordFixtures.sessionId) == ["agent-one"])

        try sandbox.writeRecord(RecordFixtures.enrolled(visible: true))
        try sandbox.hook(RecordFixtures.hookPayload("PreToolUse", extra: ["tool_name": "Bash"]))
        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == false)
        #expect(sandbox.hookLogLines().last?.hasSuffix("PreToolUse \(RecordFixtures.shortSessionId) - visible=false agents=0 tool=Bash") == true)
    }

    @Test func sessionEndDeletesTheRecordAndItsLock() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled())
        try sandbox.hook(RecordFixtures.hookPayload("SessionEnd"))

        #expect(!sandbox.exists(sandbox.recordURL(RecordFixtures.sessionId)))
        #expect(!sandbox.exists(sandbox.lockURL(RecordFixtures.sessionId)))
    }

    @Test func stopReadsFinishedSubagentsFromTheTranscript() throws {
        let sandbox = try Sandbox()
        let transcript = sandbox.home.appendingPathComponent("transcript.jsonl")
        try RecordFixtures.finishedTaskNotificationLine(agentId: "agent-one")
            .write(to: transcript, atomically: true, encoding: .utf8)
        try sandbox.writeRecord(RecordFixtures.enrolled(activeSubagents: [
            RecordFixtures.trackedSubagent("agent-one"),
            RecordFixtures.trackedSubagent("agent-two")
        ]))
        try sandbox.hook(RecordFixtures.hookPayload("Stop", extra: ["transcript_path": transcript.path]))

        let record = try #require(sandbox.record(RecordFixtures.sessionId))
        #expect(sandbox.activeSubagentIds(RecordFixtures.sessionId) == ["agent-two"])
        #expect(record["transcriptPath"] as? String == transcript.path)
        #expect((record["transcriptScanOffset"] as? Int ?? 0) > 0)
        #expect(sandbox.hookLogLines().last?.hasSuffix("visible=false agents=1 completed=1 interim=0 expired=0") == true)
    }

    @Test func aSubagentOlderThanThreeHoursExpires() throws {
        let sandbox = try Sandbox()
        let fourHoursAgo = Date().timeIntervalSince1970 - 4 * 60 * 60
        try sandbox.writeRecord(RecordFixtures.enrolled(activeSubagents: [
            RecordFixtures.trackedSubagent("agent-old", startedAt: fourHoursAgo)
        ]))
        try sandbox.hook(RecordFixtures.hookPayload("Stop"))

        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == true)
        let lines = sandbox.hookLogLines()
        #expect(lines.contains { line in line.contains("SubagentExpired \(RecordFixtures.shortSessionId) agent-old startedAt=") })
        #expect(lines.last?.hasSuffix("completed=0 interim=0 expired=1") == true)
    }

    @Test func unreadableInputAndUnknownEventsExitQuietly() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled())
        let garbage = try sandbox.run(["hook"], standardInput: "not json")
        let empty = try sandbox.run(["hook"], standardInput: "")
        let unknown = try sandbox.hook(RecordFixtures.hookPayload("PostToolUse"))

        for run in [garbage, empty, unknown] {
            #expect(run.exitStatus == 0)
            #expect(run.standardOutput.isEmpty)
            #expect(run.standardError.isEmpty)
        }
        #expect(sandbox.hookLogLines().isEmpty)
    }

    @Test func aHookForASessionWithNoRecordCreatesNoRecord() throws {
        let sandbox = try Sandbox()
        let run = try sandbox.hook(RecordFixtures.hookPayload("Stop"))

        #expect(run.exitStatus == 0)
        #expect(run.standardOutput.isEmpty)
        #expect(!sandbox.exists(sandbox.recordURL(RecordFixtures.sessionId)))
        #expect(!sandbox.exists(sandbox.daemonLog))
    }

    @Test func theSessionIdFallsBackToTheEnvironment() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled())
        try sandbox.hook(
            ["hook_event_name": "Stop"],
            environment: ["CLAUDE_CODE_SESSION_ID": RecordFixtures.sessionId]
        )

        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == true)
    }
}
