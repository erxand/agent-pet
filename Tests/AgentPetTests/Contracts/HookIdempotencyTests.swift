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

    @Test func theSameUnreportedSubagentStartTwiceCountsOnce() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(visible: true))
        let start = RecordFixtures.hookPayload("SubagentStart", extra: ["agent_type": "general-purpose", "cwd": "/work"])
        try sandbox.hook(start)
        try sandbox.hook(start)
        #expect(sandbox.activeSubagentIds(RecordFixtures.sessionId) == ["unknown-1"])
        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == false)

        let reordered = try JSONSerialization.data(withJSONObject: start, options: [.sortedKeys])
        try sandbox.run(["hook"], standardInput: String(decoding: reordered, as: UTF8.self))
        #expect(sandbox.activeSubagentIds(RecordFixtures.sessionId) == ["unknown-1"])
    }

    @Test func theSameUnreportedSubagentStopTwiceForgetsOne() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(activeSubagents: [
            RecordFixtures.trackedSubagent("unknown-1"),
            RecordFixtures.trackedSubagent("unknown-2")
        ]))
        let stop = RecordFixtures.hookPayload("SubagentStop", extra: ["agent_type": "general-purpose"])
        try sandbox.hook(stop)
        try sandbox.hook(stop)

        #expect(sandbox.activeSubagentIds(RecordFixtures.sessionId) == ["unknown-1"])
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
        #expect(record["handledHookEvents"] == nil)
        #expect(record["focusTarget"] == nil)
    }
}
