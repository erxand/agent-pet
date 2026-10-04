import AppKit
import Foundation
import Testing

enum TerminalProbe {
    static let focusableTerminalBundleIdentifiers = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "com.mitchellh.ghostty"
    ]

    static var noFocusableTerminalIsRunning: Bool {
        focusableTerminalBundleIdentifiers.allSatisfy { bundleIdentifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        }
    }
}

@Suite("focus through tmux with no config file")
struct FocusCharacterizationTests {
    private let sessionId = RecordFixtures.sessionId
    private let clientListingFormat = "#{client_tty}\t#{session_name}\t#{client_activity}"

    @Test func focusWithoutATmuxTargetExitsTwo() throws {
        let sandbox = try Sandbox()
        let missingRecord = try sandbox.run(["focus", "--session", sessionId])
        try sandbox.writeRecord(RecordFixtures.enrolled())
        let missingTarget = try sandbox.run(["focus", "--session", sessionId])

        #expect(missingRecord.exitStatus == 2)
        #expect(missingTarget.exitStatus == 2)
        #expect(missingTarget.standardError.contains("no tmux target for session \(sessionId)"))
        #expect(sandbox.tmuxCalls().isEmpty)
    }

    @Test(.enabled(if: TerminalProbe.noFocusableTerminalIsRunning))
    func focusSelectsTheWindowAndPaneAndLeavesClientsAloneWhenAsked() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(extra: ["tmuxTarget": "work:@3.%7"]))
        try sandbox.setTmuxOutput(subcommand: "list-clients", output: "/dev/ttys001\tother\t50\n")
        let run = try sandbox.run(["focus", "--session", sessionId, "--no-client-switch"])

        #expect(run.exitStatus == 0)
        #expect(sandbox.tmuxCalls() == [
            ["select-window", "-t", "work:@3"],
            ["select-pane", "-t", "%7"],
            ["list-clients", "-F", clientListingFormat]
        ])
    }

    @Test(.enabled(if: TerminalProbe.noFocusableTerminalIsRunning))
    func focusSwitchesTheMostRecentlyActiveClientToTheTargetSession() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(extra: ["tmuxTarget": "work:@3.%7"]))
        try sandbox.setTmuxOutput(
            subcommand: "list-clients",
            output: "/dev/ttys001\tother\t50\n/dev/ttys002\tthird\t90\n"
        )
        try sandbox.run(["focus", "--session", sessionId])

        #expect(sandbox.tmuxCalls() == [
            ["select-window", "-t", "work:@3"],
            ["select-pane", "-t", "%7"],
            ["list-clients", "-F", clientListingFormat],
            ["switch-client", "-c", "/dev/ttys002", "-t", "work"]
        ])
    }

    @Test(.enabled(if: TerminalProbe.noFocusableTerminalIsRunning))
    func focusSkipsTheSwitchWhenAClientIsAlreadyOnTheTargetSession() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(extra: ["tmuxTarget": "work:@3.%7"]))
        try sandbox.setTmuxOutput(
            subcommand: "list-clients",
            output: "/dev/ttys001\twork\t10\n/dev/ttys002\tthird\t90\n"
        )
        try sandbox.run(["focus", "--session", sessionId])

        #expect(sandbox.tmuxCalls().map { call in call.first ?? "" } == ["select-window", "select-pane", "list-clients"])
    }
}
