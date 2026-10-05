import Foundation
import Testing

@Suite("hooks installed globally and twice")
struct HookIdempotencyTests {
    private let events = ["Stop", "Notification", "UserPromptSubmit", "PreToolUse", "SessionEnd", "SessionStart", "SubagentStart", "SubagentStop"]

    @Test func everyEventForAnUnenrolledSessionWritesNothingAnywhere() throws {
        let sandbox = try Sandbox()
        try FileManager.default.removeItem(at: sandbox.stateDirectory)
        let transcript = sandbox.home.appendingPathComponent("transcript.jsonl")
        try "{}\n".write(to: transcript, atomically: true, encoding: .utf8)
        for event in events {
            let run = try sandbox.hook(RecordFixtures.hookPayload(event, extra: [
                "transcript_path": transcript.path,
                "notification_type": "permission_prompt",
                "agent_id": "agent-one",
                "tool_name": "Bash"
            ]))
            #expect(run.exitStatus == 0)
            #expect(run.standardOutput.isEmpty)
            #expect(run.standardError.isEmpty)
        }
        #expect(!sandbox.exists(sandbox.stateDirectory))
    }

    @Test func anUnenrolledSessionLeavesNoLockAndNoLogBesideOtherRecords() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "enrolled-session"))
        try sandbox.hook(RecordFixtures.hookPayload("PreToolUse", sessionId: "stranger", extra: ["tool_name": "Bash"]))

        #expect(!sandbox.exists(sandbox.lockURL("stranger")))
        #expect(!sandbox.exists(sandbox.recordURL("stranger")))
        #expect(sandbox.hookLogLines().isEmpty)
    }

    @Test func twoSameTypeSubagentsWithoutIdsAreTrackedApart() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled())
        let start = RecordFixtures.hookPayload("SubagentStart", extra: ["agent_type": "general-purpose", "cwd": "/work"])
        let stop = RecordFixtures.hookPayload("SubagentStop", extra: ["agent_type": "general-purpose", "cwd": "/work"])
        try sandbox.hook(start)
        try sandbox.hook(start)
        #expect(sandbox.activeSubagentIds(RecordFixtures.sessionId) == ["unknown-1", "unknown-2"])

        try sandbox.hook(stop)
        try sandbox.hook(RecordFixtures.hookPayload("Stop"))
        #expect(sandbox.activeSubagentIds(RecordFixtures.sessionId) == ["unknown-1"])
        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == false)
    }

    @Test func doubledSubagentEventsWithoutIdsBalanceOut() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled())
        let start = RecordFixtures.hookPayload("SubagentStart", extra: ["agent_type": "general-purpose"])
        let stop = RecordFixtures.hookPayload("SubagentStop", extra: ["agent_type": "general-purpose"])
        for payload in [start, start, stop, stop] {
            try sandbox.hook(payload)
        }
        try sandbox.hook(RecordFixtures.hookPayload("Stop"))

        #expect(sandbox.activeSubagentIds(RecordFixtures.sessionId).isEmpty)
        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == true)
    }

    @Test func doubledEventsWithAgentIdsLeaveTheSameStateAsSingleOnes() throws {
        let single = try Sandbox()
        let doubled = try Sandbox()
        let sequence = [
            RecordFixtures.hookPayload("SubagentStart", extra: ["agent_id": "agent-one"]),
            RecordFixtures.hookPayload("SubagentStart", extra: ["agent_id": "agent-two"]),
            RecordFixtures.hookPayload("SubagentStop", extra: ["agent_id": "agent-one"]),
            RecordFixtures.hookPayload("Stop")
        ]
        try single.writeRecord(RecordFixtures.enrolled())
        try doubled.writeRecord(RecordFixtures.enrolled())
        for payload in sequence {
            try single.hook(payload)
            try doubled.hook(payload)
            try doubled.hook(payload)
        }

        #expect(single.activeSubagentIds(RecordFixtures.sessionId) == ["agent-two"])
        #expect(doubled.activeSubagentIds(RecordFixtures.sessionId) == ["agent-two"])
        #expect(single.record(RecordFixtures.sessionId)?["visible"] as? Bool == false)
        #expect(doubled.record(RecordFixtures.sessionId)?["visible"] as? Bool == false)
    }

    @Test func eventsWithAgentIdsAddNoNewFieldToTheRecord() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled())
        try sandbox.hook(RecordFixtures.hookPayload("SubagentStart", extra: ["agent_id": "agent-one"]))
        try sandbox.hook(RecordFixtures.hookPayload("Stop"))

        let record = try #require(sandbox.record(RecordFixtures.sessionId))
        #expect(record["focusTarget"] == nil)
    }
}
