import Foundation
import Testing

@Suite("group, owner and reserved sprites from the command line")
struct GroupCommandTests {
    private let livePid = "\(getpid())"

    private func writeConfig(_ sandbox: Sandbox, _ json: String) throws {
        try json.write(to: sandbox.stateDirectory.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
    }

    private func statusEntries(_ sandbox: Sandbox) throws -> [String: [String: Any]] {
        let run = try sandbox.run(["status", "--json"])
        let report = try #require(try JSONSerialization.jsonObject(with: Data(run.standardOutput.utf8)) as? [String: Any])
        let sessions = try #require(report["sessions"] as? [[String: Any]])
        var bySessionId: [String: [String: Any]] = [:]
        for entry in sessions {
            if let sessionId = entry["sessionId"] as? String { bySessionId[sessionId] = entry }
        }
        return bySessionId
    }

    @Test func membersShareTheGroupAndTheOwnersSprite() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        try sandbox.installPack("nimbus")
        try sandbox.run(["on", "--session", "owner-1111", "--group", "dev", "--owner", "--sprite", "golem", "--pid", livePid])
        try sandbox.run(["on", "--session", "helper-2222", "--group", "dev", "--pid", livePid])

        let helper = try #require(sandbox.record("helper-2222"))
        #expect(helper["group"] as? String == "dev")
        #expect(helper["owner"] == nil)
        #expect(helper["sprite"] as? String == "golem")
        #expect(sandbox.record("owner-1111")?["owner"] as? Bool == true)

        try sandbox.run(["on", "--session", "solo-3333", "--pid", livePid])
        #expect(sandbox.record("solo-3333")?["sprite"] as? String == "nimbus")

        let entries = try statusEntries(sandbox)
        #expect(entries["owner-1111"]?["group"] as? String == "dev")
        #expect(entries["helper-2222"]?["group"] as? String == "dev")
        #expect(entries["solo-3333"]?["group"] as? String == "solo-3333")
        #expect(entries["owner-1111"]?["owner"] as? Bool == true)
        #expect(entries["helper-2222"]?["owner"] as? Bool == false)
        #expect(entries["solo-3333"]?["owner"] as? Bool == true)
    }

    @Test func withNoOwnerFlaggedTheFirstEnrolledLiveMemberOwns() throws {
        let sandbox = try Sandbox()
        try sandbox.run(["on", "--session", "first-1111", "--group", "g", "--pid", livePid])
        try sandbox.run(["on", "--session", "second-2222", "--group", "g", "--pid", livePid])
        try sandbox.run(["show", "--session", "first-1111"])

        var entries = try statusEntries(sandbox)
        #expect(entries["first-1111"]?["owner"] as? Bool == true)
        #expect(entries["second-2222"]?["owner"] as? Bool == false)

        try sandbox.run(["on", "--session", "first-1111", "--pid", "999999"])
        entries = try statusEntries(sandbox)
        #expect(entries["second-2222"]?["owner"] as? Bool == true)
    }

    @Test func flaggingANewOwnerClearsTheOldOneAndRerunningKeepsTheGroup() throws {
        let sandbox = try Sandbox()
        try sandbox.run(["on", "--session", "first-1111", "--group", "g", "--owner", "--pid", livePid])
        try sandbox.hook(RecordFixtures.hookPayload("SubagentStart", sessionId: "first-1111", extra: ["agent_id": "agent-one"]))
        try sandbox.run(["on", "--session", "second-2222", "--group", "g", "--owner", "--pid", livePid])

        #expect(sandbox.record("first-1111")?["owner"] == nil)
        #expect(sandbox.record("second-2222")?["owner"] as? Bool == true)

        try sandbox.run(["on", "--session", "first-1111", "--label", "renamed"])
        let rerun = try #require(sandbox.record("first-1111"))
        #expect(rerun["group"] as? String == "g")
        #expect(rerun["label"] as? String == "renamed")
        #expect(sandbox.activeSubagentIds("first-1111") == ["agent-one"])
    }

    @Test func reservedSpritesAreNeverPickedButStayExplicitlyAllowed() throws {
        let sandbox = try Sandbox()
        try writeConfig(sandbox, #"{"reservedSprites":["golem"]}"#)
        try sandbox.installPack("golem")
        try sandbox.installPack("nimbus")
        for index in 0..<4 {
            try sandbox.run(["on", "--session", "random-\(index)", "--pid", livePid])
            #expect(sandbox.record("random-\(index)")?["sprite"] as? String == "nimbus")
        }
        try sandbox.run(["on", "--session", "explicit", "--sprite", "golem", "--pid", livePid])
        #expect(sandbox.record("explicit")?["sprite"] as? String == "golem")
        #expect(sandbox.record("explicit")?["accent"] as? String == "green")
    }

    @Test func whenEveryPackIsReservedRandomAssignmentPicksNone() throws {
        let sandbox = try Sandbox()
        try writeConfig(sandbox, #"{"reservedSprites":["golem"]}"#)
        try sandbox.installPack("golem")
        try sandbox.run(["on", "--session", "random", "--pid", livePid])
        #expect(sandbox.record("random")?["sprite"] == nil)
    }

    @Test func aConfigWithoutTheNewKeysBehavesExactlyAsBefore() throws {
        let withoutConfig = try Sandbox()
        let withOldKeys = try Sandbox()
        try writeConfig(withOldKeys, #"{"focuser":{"kind":"tmux-iterm"},"colorSync":"tmux-color","sessionDirectories":["~/.claude/sessions"]}"#)
        var records: [[String: Any]] = []
        var outputs: [String] = []
        for sandbox in [withoutConfig, withOldKeys] {
            try sandbox.installPack("golem")
            let run = try sandbox.run(["on", "--session", RecordFixtures.sessionId, "--tmux", "work:@3.%7", "--pid", livePid])
            try sandbox.run(["show", "--session", RecordFixtures.sessionId, "--mood", "needsInput"])
            outputs.append(run.standardOutput)
            var record = try #require(sandbox.record(RecordFixtures.sessionId))
            record.removeValue(forKey: "updatedAt")
            records.append(record)
            let status = try statusEntries(sandbox)[RecordFixtures.sessionId]
            #expect(status?["group"] as? String == RecordFixtures.sessionId)
            #expect(status?["owner"] as? Bool == true)
        }
        #expect(outputs[0] == outputs[1])
        #expect(NSDictionary(dictionary: records[0]).isEqual(to: records[1]))
        #expect(Set(records[0].keys).isDisjoint(with: ["group", "owner", "enrolledAt"]))
    }
}
