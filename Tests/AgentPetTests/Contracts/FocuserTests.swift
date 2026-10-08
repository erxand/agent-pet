import Foundation
import Testing
@testable import AgentPetCore

@Suite("focusers")
struct FocuserTests {
    private func request(
        tmuxTarget: String? = "work:@3.%7",
        allowsClientSwitch: Bool = true,
        processIdentifier: Int32? = 4242,
        focusTarget: String? = "pane:12"
    ) -> FocusRequest {
        FocusRequest(
            sessionId: "focus-session",
            processIdentifier: processIdentifier,
            focusTarget: focusTarget,
            group: "focus-session",
            agent: .claudeCode,
            tmuxTarget: tmuxTarget.flatMap { rawTarget in TmuxTarget(rawValue: rawTarget) },
            allowsClientSwitch: allowsClientSwitch
        )
    }

    @Test func tmuxItermSelectsTheItermTabForTheChosenClient() {
        let tmux = RecordingTmux()
        tmux.capturedOutputBySubcommand[.listClients] = "/dev/ttys002\tother\t90\n"
        let terminals = RecordingTerminals()
        terminals.runningTerminals = [.iterm2, .appleTerminal]
        terminals.itermScriptOutput = "focused"
        TmuxItermFocuser(tmux: tmux, terminals: terminals).focus(request())

        #expect(tmux.calls == [
            ["select-window", "-t", "work:@3"],
            ["select-pane", "-t", "%7"],
            ["list-clients", "-F", TmuxClientListing.format],
            ["switch-client", "-c", "/dev/ttys002", "-t", "work"]
        ])
        #expect(terminals.itermScripts == [TmuxItermFocuser.itermFocusScript(terminalDevicePath: "/dev/ttys002")])
        #expect(terminals.itermScripts.first?.contains(#"if tty of terminalSession is "/dev/ttys002" then"#) == true)
        #expect(terminals.activatedTerminals.isEmpty)
    }

    @Test func tmuxItermFallsBackToTheFirstRunningTerminal() {
        let tmux = RecordingTmux()
        tmux.capturedOutputBySubcommand[.listClients] = "/dev/ttys002\twork\t90\n"
        let terminals = RecordingTerminals()
        terminals.runningTerminals = [.iterm2, .ghostty]
        terminals.itermScriptOutput = "not found"
        TmuxItermFocuser(tmux: tmux, terminals: terminals).focus(request())

        #expect(tmux.calls.map { call in call[0] } == ["select-window", "select-pane", "list-clients"])
        #expect(terminals.itermScripts.count == 1)
        #expect(terminals.activatedTerminals == [.iterm2])
    }

    @Test func tmuxItermWithoutClientSwitchNeverScriptsIterm() {
        let tmux = RecordingTmux()
        tmux.capturedOutputBySubcommand[.listClients] = "/dev/ttys002\tother\t90\n"
        let terminals = RecordingTerminals()
        terminals.runningTerminals = [.iterm2]
        TmuxItermFocuser(tmux: tmux, terminals: terminals).focus(request(allowsClientSwitch: false))

        #expect(!tmux.calls.contains { call in call[0] == "switch-client" })
        #expect(terminals.itermScripts.isEmpty)
        #expect(terminals.activatedTerminals == [.iterm2])
    }

    @Test func tmuxItermNeedsATmuxTargetButCommandDoesNot() {
        let tmuxItermFocuser = TmuxItermFocuser(tmux: RecordingTmux(), terminals: RecordingTerminals())
        #expect(tmuxItermFocuser.unavailability(for: request(tmuxTarget: nil)) == .missingTmuxTarget)
        #expect(tmuxItermFocuser.unavailability(for: request()) == nil)
        #expect(CommandFocuser(arguments: ["/bin/true"], waitsForCompletion: true).unavailability(for: request(tmuxTarget: nil)) == nil)
    }

    @Test func commandFocuserHandsTheSessionToTheCommand() throws {
        let directory = try TemporaryDirectory()
        let output = directory.url.appendingPathComponent("focus.out")
        let script = try directory.write("""
        #!/bin/sh
        {
          echo "args=$*"
          echo "session=$AGENT_PET_SESSION_ID"
          echo "pid=$AGENT_PET_PID"
          echo "target=$AGENT_PET_FOCUS_TARGET"
          echo "group=$AGENT_PET_GROUP"
          echo "agent=$AGENT_PET_AGENT"
          if read -r line; then echo "stdin=$line"; else echo "stdin=empty"; fi
        } > '\(output.path)'
        """, to: "focus.sh")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        var reports: [String] = []
        CommandFocuser(arguments: [script.path, "one", "two"], waitsForCompletion: true) { line in reports.append(line) }
            .focus(request())

        let lines = try String(contentsOf: output, encoding: .utf8).split(separator: "\n").map { line in String(line) }
        #expect(lines == [
            "args=one two",
            "session=focus-session",
            "pid=4242",
            "target=pane:12",
            "group=focus-session",
            "agent=claude-code",
            "stdin=empty"
        ])
        #expect(reports.isEmpty)
    }

    @Test func commandFocuserSetsEmptyValuesForWhatItDoesNotKnow() {
        let environment = CommandFocuser.environment(
            for: request(processIdentifier: nil, focusTarget: nil),
            inheriting: ["PATH": "/usr/bin"]
        )
        #expect(environment["AGENT_PET_PID"] == "")
        #expect(environment["AGENT_PET_FOCUS_TARGET"] == "")
        #expect(environment["PATH"] == "/usr/bin")
    }

    @Test func commandFocuserLogsAFailureAndAMissingCommand() throws {
        var reports: [String] = []
        CommandFocuser(arguments: ["/bin/sh", "-c", "exit 3"], waitsForCompletion: true) { line in reports.append(line) }
            .focus(request())
        CommandFocuser(arguments: ["/nonexistent/focus"], waitsForCompletion: true) { line in reports.append(line) }
            .focus(request())

        #expect(reports.first == "focus command /bin/sh exited 3")
        #expect(reports.last?.hasPrefix("focus command /nonexistent/focus could not start") == true)
    }

    @Test func commandFocuserTerminatesACommandPastItsTimeout() {
        var reports: [String] = []
        CommandFocuser(
            arguments: ["/bin/sleep", "1000"],
            timeoutInSeconds: 0.3,
            terminationGraceInSeconds: 30,
            waitsForCompletion: true
        ) { line in
            reports.append(line)
        }.focus(request())

        #expect(reports == ["focus command /bin/sleep timed out after 0.3 s and was terminated"])
    }

    @Test func commandFocuserKillsACommandThatIgnoresTermination() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("focus-trap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let ready = folder.appendingPathComponent("ready")
        var reports: [String] = []
        CommandFocuser(
            arguments: ["/bin/sh", "-c", "trap '' TERM; : > \"$0\"; while :; do sleep 0.05; done", ready.path],
            timeoutInSeconds: 0.3,
            terminationGraceInSeconds: 0.5,
            beforeTimeout: {
                let hangBound = Date().addingTimeInterval(30)
                while !FileManager.default.fileExists(atPath: ready.path) && Date() < hangBound {
                    Thread.sleep(forTimeInterval: 0.01)
                }
            },
            waitsForCompletion: true
        ) { line in
            reports.append(line)
        }.focus(request())

        #expect(FileManager.default.fileExists(atPath: ready.path))
        #expect(reports == ["focus command /bin/sh timed out after 0.3 s and was killed"])
    }
}
