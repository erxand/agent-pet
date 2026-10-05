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

extension HookIdempotencyTests {
    static let configurations: [String?] = [
        nil,
        #"{"holdWhileBusy":true,"settleSeconds":1,"subagentToolsKeepNeedsInput":true,"accentInks":true,"diveOnExit":true}"#
    ]
    private static let groupFields: [String: Any] = ["group": "win:abc", "owner": true, "enrolledAt": 2]
    private static let groupMateSessionId = "group-mate"
    private static let groupMateProcessIdentifier = 1
    private static let subagentToolStepIndex = 5
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

        init(configuration: String?) throws {
            sandbox = try Sandbox()
            transcript = sandbox.home.appendingPathComponent("transcript.jsonl")
            try "{}\n".write(to: transcript, atomically: true, encoding: .utf8)
            var extra: [String: Any] = ["label": "Dev System", "focusTarget": "pane:7"]
            if let configuration {
                try configuration.write(
                    to: sandbox.stateDirectory.appendingPathComponent("config.json"),
                    atomically: true,
                    encoding: .utf8
                )
                extra.merge(HookIdempotencyTests.groupFields) { _, groupValue in groupValue }
                try sandbox.writeRecord(RecordFixtures.enrolled(
                    sessionId: HookIdempotencyTests.groupMateSessionId,
                    extra: ["group": "win:abc", "enrolledAt": 1, "pid": HookIdempotencyTests.groupMateProcessIdentifier]
                ))
            }
            try sandbox.writeRecord(RecordFixtures.enrolled(extra: extra))
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
                    if HookIdempotencyTests.presenceOnlyKeys.contains(key) {
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
        hook("SessionEnd", sessionId: newSessionId, ["reason": "other"])
    ]

    @Test(arguments: configurations)
    func aWholeLifeOfEventsDeliveredTwiceMatchesOneDeliveryAfterEveryStep(configuration: String?) throws {
        let single = try Run(configuration: configuration)
        let doubled = try Run(configuration: configuration)
        var moodsSeen: Set<String> = []
        var handedOver = false
        for (index, step) in HookIdempotencyTests.wholeLife.enumerated() {
            try single.apply(step, deliveries: 1)
            try doubled.apply(step, deliveries: 2)
            let state = try single.petState()
            #expect(try state == doubled.petState(), "step \(index)")
            for fields in state.values where fields["visible"] == "1" {
                moodsSeen.insert(fields["mood"] ?? "")
            }
            handedOver = handedOver || state[HookIdempotencyTests.newSessionId]?["label"] == "Dev System"
            if index == HookIdempotencyTests.subagentToolStepIndex {
                let keptUp = state[RecordFixtures.sessionId]?["visible"] == "1"
                #expect(keptUp == (configuration != nil))
                #expect(state[RecordFixtures.sessionId]?["owner"] == (configuration == nil ? nil : "1"))
            }
        }
        #expect(moodsSeen == ["ready", "needsInput"])
        #expect(handedOver)
        let remaining = try single.petState()
        #expect(remaining.keys.allSatisfy { sessionId in sessionId == HookIdempotencyTests.groupMateSessionId })
        #expect((remaining[HookIdempotencyTests.groupMateSessionId] != nil) == (configuration != nil))
    }

    @Test(arguments: configurations)
    func subagentsWithoutIdsDeliveredTwiceShowAndHideTheSameAndEndTheSame(configuration: String?) throws {
        let single = try Run(configuration: configuration)
        let doubled = try Run(configuration: configuration)
        let steps: [Step] = [
            HookIdempotencyTests.hook("SubagentStart", ["agent_type": "general-purpose"]),
            HookIdempotencyTests.hook("SubagentStart", ["agent_type": "general-purpose"]),
            HookIdempotencyTests.hook("Stop"),
            HookIdempotencyTests.hook("SubagentStop", ["agent_type": "general-purpose", "last_assistant_message": "first"]),
            HookIdempotencyTests.hook("Stop"),
            HookIdempotencyTests.hook("SubagentStop", ["agent_type": "general-purpose", "last_assistant_message": "second"]),
            HookIdempotencyTests.hook("Stop")
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
