import Foundation
import Testing
@testable import AgentPetCore

@Suite("a daemon starts only where it can run")
struct DaemonStartTests {
    private final class StartLog {
        var launchAgentStarts = 0
        var spawns = 0
    }

    private func recordingStarter(_ log: StartLog) -> DaemonCommand.Starter {
        DaemonCommand.Starter(
            launchAgentIsInstalled: { false },
            startLaunchAgent: { log.launchAgentStarts += 1 },
            runningDaemon: { nil },
            parentOf: { _ in nil },
            spawnDetached: {
                log.spawns += 1
                return true
            }
        )
    }

    @Test func theNeverStartSwitchStopsBothWaysOfStartingADaemon() {
        let switchedOff = StartLog()
        let starter = recordingStarter(switchedOff).honouringNeverStart(["AGENT_PET_NEVER_START_DAEMON": "1"])
        starter.startLaunchAgent()
        #expect(!starter.spawnDetached())
        #expect(switchedOff.launchAgentStarts == 0)
        #expect(switchedOff.spawns == 0)

        for environment in [[:], ["AGENT_PET_NEVER_START_DAEMON": "0"]] {
            let log = StartLog()
            let untouched = recordingStarter(log).honouringNeverStart(environment)
            untouched.startLaunchAgent()
            #expect(untouched.spawnDetached())
            #expect(log.launchAgentStarts == 1)
            #expect(log.spawns == 1)
        }
    }

    @Test func aSandboxCommandWithNoDaemonRunningStartsNone() throws {
        let sandbox = try Sandbox()
        let pidFile = sandbox.stateDirectory.appendingPathComponent("daemon.pid")
        try FileManager.default.removeItem(at: pidFile)
        let run = try sandbox.run(["ensure-daemon"])
        #expect(run.exitStatus == 0)
        #expect(!sandbox.exists(sandbox.daemonLog))
        #expect(!sandbox.exists(pidFile))
    }

    @Test func aBinaryInAFolderMacOSGuardsIsNotDisclaimed() throws {
        let base = URL(fileURLWithPath: FileManager.default.temporaryDirectory.path)
            .appendingPathComponent("protected-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let home = base.appendingPathComponent("home", isDirectory: true)
        let build = home.appendingPathComponent("Documents/Tools/pet/.build/debug", isDirectory: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        let binary = build.appendingPathComponent("agent-pet")
        try "".write(to: binary, atomically: true, encoding: .utf8)
        let link = base.appendingPathComponent("agent-pet-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: binary)

        let protected = [
            binary.path,
            link.path,
            home.path + "/Desktop/agent-pet",
            home.path + "/Downloads/agent-pet",
            home.path + "/Library/Mobile Documents/com~apple~CloudDocs/agent-pet",
            home.path + "/Library/CloudStorage/Drive/agent-pet",
            home.path + "/Documents",
            "/Volumes/External/agent-pet"
        ]
        for path in protected {
            #expect(PrivacyProtectedFolder.contains(path, accountHome: home.path), "\(path)")
            #expect(!ResponsibilityDisclaimingSpawn.shouldDisclaim(executablePath: path, accountHome: home.path), "\(path)")
        }
        let open = [
            home.path + "/.local/bin/agent-pet",
            home.path + "/DocumentsArchive/agent-pet",
            home.path + "/Library/Application Support/agent-pet",
            "/usr/local/bin/agent-pet",
            "/opt/homebrew/bin/agent-pet"
        ]
        for path in open {
            #expect(!PrivacyProtectedFolder.contains(path, accountHome: home.path), "\(path)")
            #expect(ResponsibilityDisclaimingSpawn.shouldDisclaim(executablePath: path, accountHome: home.path), "\(path)")
        }
        #expect(!ResponsibilityDisclaimingSpawn.shouldDisclaim(executablePath: "/usr/local/bin/agent-pet", accountHome: nil))
        #expect(PrivacyProtectedFolder.accountHome() == String(cString: getpwuid(getuid()).pointee.pw_dir))
    }

    @Test func aSpawnThatMustNotDisclaimDoesNot() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("spawn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let logPath = folder.appendingPathComponent("log").path
        for disclaim in [false, true] {
            let spawned = try #require(ResponsibilityDisclaimingSpawn.spawn(
                executablePath: "/usr/bin/true",
                arguments: [],
                logPath: logPath,
                disclaim: disclaim
            ))
            var status: Int32 = 0
            waitpid(spawned.processIdentifier, &status, 0)
            #expect(spawned.disclaimed == disclaim)
        }
    }

    private final class ForegroundLog {
        var events: [String] = []
    }

    private func foreground(otherDaemon: Int32?, executableFound: Bool, log: ForegroundLog) -> DaemonCommand.Foreground {
        DaemonCommand.Foreground(
            prepare: { log.events.append("prepare") },
            otherLiveDaemon: { otherDaemon },
            ownExecutableIsFound: {
                log.events.append("look")
                return executableFound
            },
            claim: { log.events.append("claim") },
            writeError: { line in log.events.append("error: \(line)") }
        )
    }

    @Test func aDaemonThatCannotFindItsOwnExecutableExitsBeforeTouchingTheWindowServer() {
        let missing = ForegroundLog()
        let refused = DaemonCommand.runInForeground(using: foreground(otherDaemon: nil, executableFound: false, log: missing)) {
            missing.events.append("overlay")
        }
        #expect(refused == 1)
        #expect(missing.events == ["prepare", "look", "error: \(DaemonCommand.ownExecutableMissingMessage)"])

        let found = ForegroundLog()
        let ran = DaemonCommand.runInForeground(using: foreground(otherDaemon: nil, executableFound: true, log: found)) {
            found.events.append("overlay")
        }
        #expect(ran == 0)
        #expect(found.events == ["prepare", "look", "claim", "overlay"])

        let second = ForegroundLog()
        let left = DaemonCommand.runInForeground(using: foreground(otherDaemon: 77, executableFound: true, log: second)) {
            second.events.append("overlay")
        }
        #expect(left == 0)
        #expect(second.events == ["prepare"])
        #expect(OwnExecutable.isFoundThroughMainBundle())
    }
}
