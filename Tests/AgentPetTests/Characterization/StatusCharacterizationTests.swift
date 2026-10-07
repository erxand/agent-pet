import Foundation
import Testing

@Suite("status, labels, liveness and old records with no config file")
struct StatusCharacterizationTests {
    private static let deadProcessIdentifier: Int32 = 999_999

    private func statusRows(_ sandbox: Sandbox) throws -> [String: [String]] {
        let run = try sandbox.run(["status"])
        #expect(run.exitStatus == 0)
        var rowsByShortId: [String: [String]] = [:]
        for line in run.standardOutput.split(separator: "\n").dropFirst() where !line.hasPrefix("daemon pid:") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map { field in String(field) }
            guard let shortId = fields.first else { continue }
            rowsByShortId[shortId] = fields
        }
        return rowsByShortId
    }

    @Test func theHeaderAndDaemonLineAreStable() throws {
        let sandbox = try Sandbox()
        let run = try sandbox.run(["status"])
        let lines = run.standardOutput.split(separator: "\n").map { line in String(line) }
        let columns: [(String, Int)] = [
            ("SESSION", 10), ("LABEL", 24), ("SPRITE", 10), ("ACCENT", 8), ("ENABLED", 8),
            ("VISIBLE", 8), ("MOOD", 11), ("AGENTS", 7)
        ]
        let expectedHeader = columns
            .map { title, width in title.padding(toLength: width, withPad: " ", startingAt: 0) }
            .joined(separator: "  ") + "  ALIVE"
        #expect(lines.first == expectedHeader)
        #expect(lines.last == "daemon pid: \(getpid())")
    }

    @Test func labelsResolveNicknameThenLabelThenSessionNameThenWorkingDirectory() throws {
        let sandbox = try Sandbox()
        let liveProcess = getpid()
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "aaaaaaaa-1", extra: ["nickname": "nick", "label": "lab"]))
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "bbbbbbbb-1", extra: ["label": "lab"]))
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "cccccccc-1", extra: ["pid": NSNull()]))
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "dddddddd-1", extra: ["pid": NSNull()]))
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "eeeeeeee-1"))
        try sandbox.writeClaudeSession(processIdentifier: liveProcess, sessionId: "cccccccc-1", name: "renamed", cwd: "/tmp/ignored")
        try sandbox.writeClaudeSession(processIdentifier: liveProcess + 1_000_000, sessionId: "dddddddd-1", cwd: "/work/repo-name")

        let rows = try statusRows(sandbox)
        #expect(rows["aaaaaaaa"]?[1] == "nick")
        #expect(rows["bbbbbbbb"]?[1] == "lab")
        #expect(rows["cccccccc"]?[1] == "renamed")
        #expect(rows["dddddddd"]?[1] == "repo-name")
        #expect(rows["eeeeeeee"]?[1] == "session")
    }

    @Test func livenessFollowsThePidThenTheClaudeSessionFileThenTheGracePeriod() throws {
        let sandbox = try Sandbox()
        let sixtySecondsAgo = Date().timeIntervalSince1970 - 60
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "aaaaaaaa-1"))
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "bbbbbbbb-1", extra: ["pid": Int(Self.deadProcessIdentifier)]))
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "cccccccc-1", extra: ["pid": NSNull()]))
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "dddddddd-1", extra: ["pid": NSNull(), "updatedAt": sixtySecondsAgo]))
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "eeeeeeee-1", extra: ["pid": NSNull(), "updatedAt": sixtySecondsAgo]))
        try sandbox.writeRecord(RecordFixtures.enrolled(sessionId: "ffffffff-1", extra: ["pid": NSNull(), "agent": "pi", "updatedAt": sixtySecondsAgo]))
        try sandbox.writeClaudeSession(processIdentifier: getpid(), sessionId: "eeeeeeee-1")

        let rows = try statusRows(sandbox)
        #expect(rows["aaaaaaaa"]?.last == "yes")
        #expect(rows["bbbbbbbb"]?.last == "no")
        #expect(rows["cccccccc"]?.last == "yes")
        #expect(rows["dddddddd"]?.last == "no")
        #expect(rows["eeeeeeee"]?.last == "yes")
        #expect(rows["ffffffff"]?.last == "yes")
    }

    @Test func aRecordFromBeforeActiveSubagentsStillDecodes() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord([
            "sessionId": RecordFixtures.sessionId,
            "pid": Int(getpid()),
            "activeSubagentIds": ["legacy-one", "legacy-two"],
            "updatedAt": Date().timeIntervalSince1970
        ])

        let row = try #require(try statusRows(sandbox)[RecordFixtures.shortSessionId])
        #expect(row == [RecordFixtures.shortSessionId, "session", "claude", row[3], "yes", "no", "ready", "2", "yes"])

        try sandbox.hook(RecordFixtures.hookPayload("SubagentStop", extra: ["agent_id": "legacy-one"]))
        #expect(sandbox.activeSubagentIds(RecordFixtures.sessionId) == ["legacy-two"])
    }

    @Test func aMinimalRecordDecodesWithDefaults() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(["sessionId": RecordFixtures.sessionId, "pid": Int(getpid())])
        try sandbox.hook(RecordFixtures.hookPayload("Stop"))

        let record = try #require(sandbox.record(RecordFixtures.sessionId))
        #expect(record["enabled"] as? Bool == true)
        #expect(record["visible"] as? Bool == true)
        #expect(record["agent"] as? String == "claude-code")
    }
}
