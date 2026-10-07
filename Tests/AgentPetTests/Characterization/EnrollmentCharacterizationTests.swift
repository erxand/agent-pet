import Foundation
import Testing

@Suite("enrollment with no config file")
struct EnrollmentCharacterizationTests {
    private let sessionId = RecordFixtures.sessionId

    @Test func onWritesAnEnabledHiddenRecordWithTheOnlyPackAndItsAccent() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        let run = try sandbox.run(["on", "--session", sessionId])

        #expect(run.exitStatus == 0)
        #expect(run.standardOutput == "pet on for session, sprite golem, accent green\n")
        let record = try #require(sandbox.record(sessionId))
        #expect(record["enabled"] as? Bool == true)
        #expect(record["visible"] as? Bool == false)
        #expect(record["sprite"] as? String == "golem")
        #expect(record["accent"] as? String == "green")
        #expect(record["agent"] as? String == "claude-code")
        #expect(record["tmuxTarget"] == nil)
        #expect(sandbox.tmuxCalls().isEmpty)
        #expect(sandbox.startedNoDaemon)
    }

    @Test func withNoPacksTheRecordHasNoSpriteAndTheAccentComesFromTheSessionId() throws {
        let sandbox = try Sandbox()
        let run = try sandbox.run(["on", "--session", sessionId])

        let record = try #require(sandbox.record(sessionId))
        #expect(record["sprite"] == nil)
        #expect(record["accent"] == nil)
        #expect(run.standardOutput.hasPrefix("pet on for session, sprite claude, accent "))
    }

    @Test func theSessionIdComesFromTheEnvironmentOrTheCommandFails() throws {
        let sandbox = try Sandbox()
        let missing = try sandbox.run(["on"])
        #expect(missing.exitStatus == 2)
        #expect(missing.standardError.contains("no session id"))

        let fromEnvironment = try sandbox.run(["on"], environment: ["CLAUDE_CODE_SESSION_ID": sessionId])
        #expect(fromEnvironment.exitStatus == 0)
        #expect(sandbox.record(sessionId) != nil)
    }

    @Test func aNewSessionGetsTheLeastUsedPack() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        try sandbox.installPack("nimbus")
        let liveProcess = "\(getpid())"
        try sandbox.run(["on", "--session", "first-session", "--sprite", "golem", "--pid", liveProcess])
        try sandbox.run(["on", "--session", "second-session", "--pid", liveProcess])

        #expect(sandbox.record("second-session")?["sprite"] as? String == "nimbus")
        #expect(sandbox.record("second-session")?["accent"] as? String == "blue")
    }

    @Test func explicitSpriteAndAccentWinAndAreKeptOnReenrollment() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        try sandbox.installPack("nimbus")
        let run = try sandbox.run(["on", "--session", sessionId, "--sprite", "nimbus", "--accent", "pink", "--nickname", "pal"])
        #expect(run.standardOutput == "pet on for pal, sprite nimbus, accent pink\n")

        try sandbox.run(["on", "--session", sessionId])
        let record = try #require(sandbox.record(sessionId))
        #expect(record["sprite"] as? String == "nimbus")
        #expect(record["accent"] as? String == "pink")
        #expect(record["nickname"] as? String == "pal")
    }

    @Test func reenrollmentKeepsTrackedSubagents() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(activeSubagents: [RecordFixtures.trackedSubagent("agent-one")]))
        try sandbox.run(["on", "--session", sessionId])

        #expect(sandbox.activeSubagentIds(sessionId) == ["agent-one"])
    }

    @Test func badFlagValuesAreRejected() throws {
        let sandbox = try Sandbox()
        let accent = try sandbox.run(["on", "--session", sessionId, "--accent", "mauve"])
        let agent = try sandbox.run(["on", "--session", sessionId, "--agent", "robot"])
        let processIdentifier = try sandbox.run(["on", "--session", sessionId, "--pid", "abc"])

        #expect(accent.exitStatus == 2)
        #expect(agent.exitStatus == 2)
        #expect(processIdentifier.exitStatus == 2)
        #expect(sandbox.record(sessionId) == nil)
    }

    @Test func onTypesTheAccentIntoTheTmuxPaneAndOffResetsIt() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        try sandbox.run(["on", "--session", sessionId, "--tmux", "work:@3.%7"])
        try sandbox.run(["off", "--session", sessionId])

        #expect(sandbox.tmuxCalls() == [
            ["send-keys", "-t", "work:@3.%7", "-l", "/color green"],
            ["send-keys", "-t", "work:@3.%7", "Enter"],
            ["send-keys", "-t", "work:@3.%7", "-l", "/color default"],
            ["send-keys", "-t", "work:@3.%7", "Enter"]
        ])
        let record = try #require(sandbox.record(sessionId))
        #expect(record["enabled"] as? Bool == false)
        #expect(record["visible"] as? Bool == false)
    }

    @Test func colorSyncIsSkippedOnRequestAndForPi() throws {
        let sandbox = try Sandbox()
        try sandbox.run(["on", "--session", "skip-session", "--tmux", "work:@3.%7", "--no-color-sync"])
        try sandbox.run(["on", "--session", "pi-session", "--tmux", "work:@3.%7", "--agent", "pi"])
        try sandbox.run(["off", "--session", "skip-session", "--no-color-sync"])

        #expect(sandbox.tmuxCalls().isEmpty)
    }

    @Test func theTmuxTargetIsResolvedFromTheCallersPane() throws {
        let sandbox = try Sandbox()
        try sandbox.setTmuxOutput(subcommand: "display-message", output: "work:@3.%7\n")
        try sandbox.run(["on", "--session", sessionId, "--no-color-sync"], environment: ["TMUX_PANE": "%7"])

        #expect(sandbox.record(sessionId)?["tmuxTarget"] as? String == "work:@3.%7")
        #expect(sandbox.tmuxCalls() == [
            ["display-message", "-p", "-t", "%7", "#{session_name}:#{window_id}.#{pane_id}"]
        ])
    }

    @Test func showHideAndRemove() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled())
        try sandbox.run(["show", "--session", sessionId, "--mood", "blocked", "--message", "stuck"])
        var record = try #require(sandbox.record(sessionId))
        #expect(record["visible"] as? Bool == true)
        #expect(record["mood"] as? String == "blocked")
        #expect(record["message"] as? String == "stuck")

        try sandbox.run(["hide", "--session", sessionId])
        record = try #require(sandbox.record(sessionId))
        #expect(record["visible"] as? Bool == false)

        try sandbox.run(["remove", "--session", sessionId])
        #expect(sandbox.record(sessionId) == nil)
        #expect(sandbox.startedNoDaemon)
    }

    @Test func showOnAnUnenrolledOrDisabledSessionIsANoOp() throws {
        let sandbox = try Sandbox()
        let unenrolled = try sandbox.run(["show", "--session", sessionId])
        #expect(unenrolled.exitStatus == 0)
        #expect(sandbox.record(sessionId) == nil)

        try sandbox.writeRecord(RecordFixtures.enrolled(enabled: false))
        try sandbox.run(["show", "--session", sessionId])
        #expect(sandbox.record(sessionId)?["visible"] as? Bool == false)
    }

    @Test func clearSubagentsReportsWhatItDropped() throws {
        let sandbox = try Sandbox()
        let missing = try sandbox.run(["clear-subagents", "--session", sessionId])
        #expect(missing.exitStatus == 2)

        try sandbox.writeRecord(RecordFixtures.enrolled(activeSubagents: [
            RecordFixtures.trackedSubagent("agent-one"),
            RecordFixtures.trackedSubagent("agent-two")
        ]))
        let run = try sandbox.run(["clear-subagents", "--session", sessionId])
        #expect(run.standardOutput == "cleared 2 tracked subagents for \(sessionId)\n")
        #expect(sandbox.activeSubagentIds(sessionId).isEmpty)
    }
}
