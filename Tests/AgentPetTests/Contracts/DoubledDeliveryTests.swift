import Foundation
import Testing

@Suite("every hook event delivered twice ends where one delivery does")
struct DoubledDeliveryTests {
    private static let newSessionId = "99999999-8888-7777-6666-555555555555"
    private static let presenceOnlyKeys: Set<String> = [
        "updatedAt", "waitingSince", "handoverPendingSince", "enrolledAt", "transcriptPath"
    ]

    private enum Step {
        case hook([String: Any])
        case transcriptLine(String)
    }

    private struct Run {
        let sandbox: Sandbox
        let transcript: URL

        init() throws {
            sandbox = try Sandbox()
            transcript = sandbox.home.appendingPathComponent("transcript.jsonl")
            try "{}\n".write(to: transcript, atomically: true, encoding: .utf8)
            try sandbox.writeRecord(RecordFixtures.enrolled(extra: ["label": "Dev System", "focusTarget": "pane:7"]))
        }

        func apply(_ step: Step, deliveries: Int) throws {
            switch step {
            case .hook(var payload):
                payload["transcript_path"] = transcript.path
                for _ in 0..<deliveries {
                    try sandbox.hook(payload)
                }
            case .transcriptLine(let line):
                let handle = try FileHandle(forWritingTo: transcript)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            }
        }

        func petState() throws -> [String: [String: String]] {
            let fileNames = try FileManager.default.contentsOfDirectory(atPath: sandbox.sessionsDirectory.path)
            var state: [String: [String: String]] = [:]
            for fileName in fileNames where fileName.hasSuffix(".json") {
                let sessionId = String(fileName.dropLast(".json".count))
                guard let record = sandbox.record(sessionId) else { continue }
                var fields: [String: String] = [:]
                for (key, value) in record {
                    if DoubledDeliveryTests.presenceOnlyKeys.contains(key) {
                        fields[key] = "present"
                    } else if key == "activeSubagents" {
                        fields[key] = sandbox.activeSubagentIds(sessionId).sorted().joined(separator: ",")
                    } else {
                        fields[key] = "\(value)"
                    }
                }
                state[sessionId] = fields
            }
            return state
        }
    }

    private static func hook(_ eventName: String, sessionId: String = RecordFixtures.sessionId, _ extra: [String: Any] = [:]) -> Step {
        .hook(RecordFixtures.hookPayload(eventName, sessionId: sessionId, extra: extra))
    }

    private static let wholeLife: [Step] = [
        hook("UserPromptSubmit"),
        hook("PreToolUse", ["tool_name": "Bash"]),
        hook("SubagentStart", ["agent_id": "agent-front", "agent_type": "general-purpose"]),
        hook("SubagentStart", ["agent_id": "agent-back", "agent_type": "general-purpose"]),
        hook("Notification", ["notification_type": "permission_prompt"]),
        hook("PreToolUse", ["agent_id": "agent-front", "tool_name": "Bash"]),
        hook("SubagentStop", ["agent_id": "agent-front"]),
        hook("Stop", ["last_assistant_message": "Still working on it"]),
        .transcriptLine(RecordFixtures.finishedTaskNotificationLine(agentId: "agent-back")),
        hook("Stop", ["last_assistant_message": "All done\nmore"]),
        hook("Notification", ["notification_type": "idle_prompt"]),
        hook("Notification", ["notification_type": "elicitation_dialog"]),
        hook("UserPromptSubmit"),
        hook("Stop"),
        hook("SessionEnd", ["reason": "clear"]),
        hook("SessionStart", sessionId: newSessionId, ["source": "clear"]),
        hook("UserPromptSubmit", sessionId: newSessionId),
        hook("Stop", sessionId: newSessionId, ["last_assistant_message": "Fresh start"]),
        hook("SessionEnd", sessionId: newSessionId, ["reason": "resume"]),
        hook("SessionStart", sessionId: newSessionId, ["source": "resume"]),
        hook("SessionStart", sessionId: newSessionId, ["source": "startup"]),
        hook("Stop", sessionId: newSessionId),
        hook("SessionEnd", sessionId: newSessionId, ["reason": "prompt_input_exit"])
    ]

    @Test func aWholeLifeOfEventsWithIdsMatchesAfterEveryStep() throws {
        let single = try Run()
        let doubled = try Run()
        var moodsSeen: Set<String> = []
        var handedOver = false
        for (index, step) in DoubledDeliveryTests.wholeLife.enumerated() {
            try single.apply(step, deliveries: 1)
            try doubled.apply(step, deliveries: 2)
            let state = try single.petState()
            #expect(try state == doubled.petState(), "step \(index)")
            for fields in state.values where fields["visible"] == "1" {
                moodsSeen.insert(fields["mood"] ?? "")
            }
            handedOver = handedOver || state[DoubledDeliveryTests.newSessionId]?["label"] == "Dev System"
        }
        #expect(moodsSeen == ["ready", "needsInput"])
        #expect(handedOver)
        #expect(try single.petState().isEmpty)
    }

    @Test func subagentsWithoutIdsShowAndHideTheSameAndEndTheSame() throws {
        let single = try Run()
        let doubled = try Run()
        let steps: [Step] = [
            DoubledDeliveryTests.hook("SubagentStart", ["agent_type": "general-purpose"]),
            DoubledDeliveryTests.hook("SubagentStart", ["agent_type": "general-purpose"]),
            DoubledDeliveryTests.hook("Stop"),
            DoubledDeliveryTests.hook("SubagentStop", ["agent_type": "general-purpose", "last_assistant_message": "first"]),
            DoubledDeliveryTests.hook("Stop"),
            DoubledDeliveryTests.hook("SubagentStop", ["agent_type": "general-purpose", "last_assistant_message": "second"]),
            DoubledDeliveryTests.hook("Stop")
        ]
        for (index, step) in steps.enumerated() {
            try single.apply(step, deliveries: 1)
            try doubled.apply(step, deliveries: 2)
            let singleRecord = single.sandbox.record(RecordFixtures.sessionId)
            let doubledRecord = doubled.sandbox.record(RecordFixtures.sessionId)
            #expect(singleRecord?["visible"] as? Bool == doubledRecord?["visible"] as? Bool, "step \(index)")
            #expect(singleRecord?["busy"] as? Bool == doubledRecord?["busy"] as? Bool, "step \(index)")
        }
        #expect(try single.petState() == doubled.petState())
        #expect(single.sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == true)
    }
}
