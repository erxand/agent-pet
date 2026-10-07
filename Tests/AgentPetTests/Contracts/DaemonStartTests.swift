import Foundation
import Testing
@testable import AgentPetCore

@Suite("a daemon starts only for this account's own home and where it can run")
struct DaemonStartTests {
    private final class StartLog {
        var launchAgentStarts = 0
        var spawns = 0
        var probes = 0
    }

    private func recordingStarter(homeIsForeign: Bool, running: Int32?, agent: Bool, log: StartLog) -> DaemonCommand.Starter {
        DaemonCommand.Starter(
            homeIsForeign: { homeIsForeign },
            launchAgentIsInstalled: { agent },
            startLaunchAgent: { log.launchAgentStarts += 1 },
            runningDaemon: {
                log.probes += 1
                return running
            },
            parentOf: { _ in ProcessParent.launchd },
            spawnDetached: {
                log.spawns += 1
                return true
            }
        )
    }

    @Test func aForeignHomeNeitherKickstartsNorSpawns() {
        for (running, agent) in [(Int32?.none, false), (nil, true), (7, true), (7, false)] {
            let log = StartLog()
            let start = DaemonCommand.ensureRunningOnItsOwn(
                using: recordingStarter(homeIsForeign: true, running: running, agent: agent, log: log)
            )
            #expect(start == .refusedForeignHome)
            #expect(log.launchAgentStarts == 0)
            #expect(log.spawns == 0)
            #expect(log.probes == 0)
        }
        let log = StartLog()
        let start = DaemonCommand.ensureRunningOnItsOwn(using: recordingStarter(homeIsForeign: false, running: nil, agent: false, log: log))
        #expect(start == .spawnedOnItsOwn)
        #expect(log.spawns == 1)
    }

    @Test func theLaunchAgentIsNeverTouchedForAForeignHome() {
        var calls: [LaunchctlSubcommand] = []
        LaunchAgent.start(homeIsForeign: { true }) { subcommand, _ in
            calls.append(subcommand)
            return .failed
        }
        #expect(calls.isEmpty)
        LaunchAgent.start(homeIsForeign: { false }) { subcommand, _ in
            calls.append(subcommand)
            return .failed
        }
        #expect(calls == [.kickstart, .bootstrap])
    }

    @Test func theSpawnIsNeverMadeForAForeignHome() {
        var spawns = 0
        #expect(!DaemonCommand.spawnDetached(homeIsForeign: { true }) {
            spawns += 1
            return true
        })
        #expect(spawns == 0)
        #expect(DaemonCommand.spawnDetached(homeIsForeign: { false }) {
            spawns += 1
            return true
        })
        #expect(spawns == 1)
    }

    @Test func aSandboxHomeIsRefusedAndSaidSo() throws {
        let sandbox = try Sandbox()
        #expect(AccountHome.isForeign(homeInUse: sandbox.home.path, accountHome: PrivacyProtectedFolder.accountHome()))
        for arguments in [["ensure-daemon"], ["dock-access", "--ask"]] {
            let run = try sandbox.run(arguments)
            #expect(run.exitStatus == 1, "\(arguments)")
            #expect(run.standardError == "agent-pet: \(AccountHome.foreignHomeMessage)\n", "\(arguments)")
        }
        #expect(!sandbox.exists(sandbox.stateDirectory.appendingPathComponent("control/dock-access-ask")))
        #expect(!sandbox.exists(sandbox.daemonLog))
    }

    @Test func theHomeInUseIsComparedWithTheAccountsAfterResolvingLinks() throws {
        let base = URL(fileURLWithPath: FileManager.default.temporaryDirectory.path)
            .appendingPathComponent("homes-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let home = base.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let link = base.appendingPathComponent("home-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: home)
        #expect(!AccountHome.isForeign(homeInUse: home.path, accountHome: home.path))
        #expect(!AccountHome.isForeign(homeInUse: link.path, accountHome: home.path))
        #expect(!AccountHome.isForeign(homeInUse: home.path + "/", accountHome: home.path))
        #expect(AccountHome.isForeign(homeInUse: base.appendingPathComponent("other").path, accountHome: home.path))
        #expect(AccountHome.isForeign(homeInUse: home.path, accountHome: nil))
        let accountHome = try #require(PrivacyProtectedFolder.accountHome())
        #expect(!AccountHome.isForeign(homeInUse: "/System/Volumes/Data" + accountHome, accountHome: accountHome))
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
        let accountHome = try #require(PrivacyProtectedFolder.accountHome())

        let protected = [
            (binary.path, home.path),
            (link.path, home.path),
            (home.path + "/Desktop/agent-pet", home.path),
            (home.path + "/Downloads/agent-pet", home.path),
            (home.path + "/Library/Mobile Documents/com~apple~CloudDocs/agent-pet", home.path),
            (home.path + "/Library/CloudStorage/Drive/agent-pet", home.path),
            (home.path + "/Documents", home.path),
            ("/Volumes/External/agent-pet", home.path),
            ("/Network/Servers/agent-pet", home.path),
            ("/System/Volumes/Data" + accountHome + "/Documents/agent-pet", accountHome)
        ]
        for (path, owner) in protected {
            #expect(PrivacyProtectedFolder.contains(path, accountHome: owner), "\(path)")
            #expect(!ResponsibilityDisclaimingSpawn.shouldDisclaim(executablePath: path, accountHome: owner), "\(path)")
        }
        let open = [
            home.path + "/.local/bin/agent-pet",
            home.path + "/DocumentsArchive/agent-pet",
            home.path + "/Library/Application Support/agent-pet",
            "/usr/local/bin/agent-pet",
            "/opt/homebrew/bin/agent-pet",
            "/VolumesArchive/agent-pet"
        ]
        for path in open {
            #expect(!PrivacyProtectedFolder.contains(path, accountHome: home.path), "\(path)")
            #expect(ResponsibilityDisclaimingSpawn.shouldDisclaim(executablePath: path, accountHome: home.path), "\(path)")
        }
        #expect(!ResponsibilityDisclaimingSpawn.shouldDisclaim(executablePath: "/usr/local/bin/agent-pet", accountHome: nil))
        #expect(accountHome == String(cString: getpwuid(getuid()).pointee.pw_dir))
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

    private func foreground(
        foreignHome: Bool = false,
        otherDaemon: Int32?,
        executableFound: Bool,
        log: ForegroundLog
    ) -> DaemonCommand.Foreground {
        DaemonCommand.Foreground(
            homeIsForeign: { foreignHome },
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

    @Test func aDaemonThatCannotRunExitsBeforeTouchingTheWindowServer() {
        let foreign = ForegroundLog()
        let refusedHome = DaemonCommand.runInForeground(
            using: foreground(foreignHome: true, otherDaemon: nil, executableFound: true, log: foreign)
        ) { foreign.events.append("overlay") }
        #expect(refusedHome == 1)
        #expect(foreign.events == ["error: \(AccountHome.foreignHomeMessage)"])

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
    }

    @Test func theExecutableIsFoundOnlyWhenTheMainBundleNamesIt() {
        let bundle = CFBundleGetMainBundle() as CFBundle?
        #expect(!OwnExecutable.isFoundThroughMainBundle(mainBundle: { nil }, executableURL: { _ in
            Issue.record("no bundle, so nothing to ask")
            return nil
        }))
        #expect(!OwnExecutable.isFoundThroughMainBundle(mainBundle: { bundle }, executableURL: { _ in nil }))
        let anyURL = URL(fileURLWithPath: "/usr/bin/true") as CFURL
        #expect(OwnExecutable.isFoundThroughMainBundle(mainBundle: { bundle }, executableURL: { _ in anyURL }))
        #expect(OwnExecutable.isFoundThroughMainBundle())
    }
}
