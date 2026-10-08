import Foundation
import Testing
@testable import AgentPetCore

@Suite("a daemon starts only for this account's own home and where it can run")
struct DaemonStartTests {
    private final class StartLog {
        var launchAgentStarts = 0
        var spawns = 0
        var probes = 0
        var prepares = 0
    }

    private func recordingStarter(homeIsForeign: Bool, running: Int32?, agent: Bool, log: StartLog) -> DaemonCommand.Starter {
        DaemonCommand.Starter(
            homeIsForeign: { homeIsForeign },
            prepare: { log.prepares += 1 },
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
            #expect(log.prepares == 0)
        }
        let log = StartLog()
        let start = DaemonCommand.ensureRunningOnItsOwn(using: recordingStarter(homeIsForeign: false, running: nil, agent: false, log: log))
        #expect(start == .spawnedOnItsOwn)
        #expect(log.spawns == 1)
        #expect(log.prepares == 1)
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
        var probes = AccountHome.Probes.live
        probes.homeInUse = { sandbox.home.path }
        #expect(AccountHome.verdict(probes) == .foreign)
        for arguments in [["ensure-daemon"], ["dock-access", "--ask"]] {
            let run = try sandbox.run(arguments)
            #expect(run.exitStatus == 1, "\(arguments)")
            #expect(run.standardError == "agent-pet: \(AccountHome.foreignHomeMessage)\n", "\(arguments)")
        }
        #expect(!sandbox.exists(sandbox.stateDirectory.appendingPathComponent("control/dock-access-ask")))
        #expect(!sandbox.exists(sandbox.daemonLog))
    }

    private func probes(
        homeInUse: String = "/Users/pet",
        entry: String? = "/Users/pet",
        reentrantEntry: String? = "/Users/pet",
        userName: String = "pet",
        identities: [String: FileIdentity]
    ) -> AccountHome.Probes {
        AccountHome.Probes(
            homeInUse: { homeInUse },
            passwordEntryHome: { entry },
            reentrantPasswordEntryHome: { reentrantEntry },
            userName: { userName },
            identity: { path in identities[path] }
        )
    }

    @Test func theSameFolderIsKnownByItsDeviceAndInodeNotItsSpelling() {
        let home = FileIdentity(device: 1, inode: 500)
        let elsewhere = FileIdentity(device: 1, inode: 501)
        #expect(AccountHome.verdict(probes(homeInUse: "/users/PET", identities: ["/Users/pet": home, "/users/PET": home])) == .own)
        #expect(AccountHome.verdict(probes(identities: ["/Users/pet": home])) == .own)
        #expect(AccountHome.verdict(probes(homeInUse: "/tmp/sandbox", identities: ["/Users/pet": home, "/tmp/sandbox": elsewhere])) == .foreign)
        #expect(AccountHome.isSameFolder("/a", "/a", identity: { path in path == "/a" ? home : nil }))
        var asked = 0
        #expect(!AccountHome.isSameFolder("/mounted/over", "/mounted/over", identity: { _ in
            asked += 1
            return asked == 1 ? home : elsewhere
        }))
        var calls = 0
        #expect(!AccountHome.isSameFolder("/one", "/two", identity: { path in
            calls += 1
            return path == "/one" ? home : FileIdentity(device: 2, inode: 500)
        }))
        #expect(calls == 2)
    }

    @Test func withoutAnIdentityThePathsAreComparedAfterResolvingLinks() throws {
        let base = URL(fileURLWithPath: FileManager.default.temporaryDirectory.path)
            .appendingPathComponent("homes-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let home = base.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let link = base.appendingPathComponent("home-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: home)
        let noIdentity: (String) -> FileIdentity? = { _ in nil }
        #expect(AccountHome.isSameFolder(link.path, home.path, identity: noIdentity))
        #expect(AccountHome.isSameFolder(home.path + "/", home.path, identity: noIdentity))
        #expect(!AccountHome.isSameFolder(base.appendingPathComponent("other").path, home.path, identity: noIdentity))
        #expect(AccountHome.isSameFolder(link.path, home.path, identity: FileIdentity.of))
        #expect(!AccountHome.isSameFolder(base.path, home.path, identity: FileIdentity.of))
        let accountHome = try #require(AccountHome.home())
        #expect(AccountHome.isSameFolder("/System/Volumes/Data" + accountHome, accountHome, identity: noIdentity))
        #expect(AccountHome.isSameFolder("/System/Volumes/Data" + accountHome, accountHome, identity: FileIdentity.of))
    }

    @Test func theAccountHomeFallsBackUntilOneExists() {
        let home = FileIdentity(device: 1, inode: 500)
        let mounted = ["/Users/pet": home]
        #expect(AccountHome.home(probes(entry: nil, identities: mounted)) == "/Users/pet")
        #expect(AccountHome.home(probes(entry: "/Volumes/Homes/pet", identities: mounted)) == "/Users/pet")
        #expect(AccountHome.home(probes(entry: "/Volumes/Homes/pet", reentrantEntry: "/Network/pet", identities: mounted)) == "/Users/pet")
        #expect(AccountHome.home(probes(
            entry: "/Volumes/Homes/pet",
            reentrantEntry: "/Network/pet",
            identities: ["/Network/pet": home, "/Users/pet": home]
        )) == "/Network/pet")
        #expect(AccountHome.home(probes(
            entry: "/Volumes/Homes/pet",
            identities: ["/Volumes/Homes/pet": home, "/Users/pet": home]
        )) == "/Volumes/Homes/pet")
        #expect(AccountHome.home(probes(entry: nil, reentrantEntry: nil, userName: "", identities: ["/Users/": home])) == nil)

        let lost = probes(entry: "/Volumes/Homes/pet", reentrantEntry: nil, identities: [:])
        #expect(AccountHome.verdict(lost) == .accountHomeNotFound)
        #expect(AccountHome.refusalMessage(lost) == AccountHome.accountHomeNotFoundMessage)
        let foreign = probes(homeInUse: "/tmp/sandbox", identities: mounted)
        #expect(AccountHome.refusalMessage(foreign) == AccountHome.foreignHomeMessage)
        #expect(AccountHome.verdict(.live) == .own)
        #expect(AccountHome.home() == String(cString: getpwuid(getuid()).pointee.pw_dir))
    }

    @Test func aSilentCallerNotesTheRefusalOnceAnHourWhereStateAlreadyExists() throws {
        let base = URL(fileURLWithPath: FileManager.default.temporaryDirectory.path)
            .appendingPathComponent("notice-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let state = base.appendingPathComponent(".agent-pet", isDirectory: true)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(!ForeignHomeNotice.note("refused", stateDirectory: state, now: start))
        #expect(!FileManager.default.fileExists(atPath: base.path))

        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        let log = state.appendingPathComponent("daemon.log")
        func lines() throws -> [String] {
            try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
        }
        #expect(ForeignHomeNotice.note("refused", stateDirectory: state, now: start))
        #expect(try lines().count == 1)
        #expect(try lines().first?.hasSuffix(" agent-pet: refused") == true)
        #expect(!ForeignHomeNotice.note("refused", stateDirectory: state, now: start.addingTimeInterval(3599)))
        #expect(try lines().count == 1)
        #expect(ForeignHomeNotice.note("refused", stateDirectory: state, now: start.addingTimeInterval(3600)))
        #expect(try lines().count == 2)
        #expect(ForeignHomeNotice.note("refused", stateDirectory: state, now: start.addingTimeInterval(1000)))
        #expect(try lines().count == 3)
    }

    @Test func aSandboxSessionCommandLeavesTheNoticeInItsOwnDaemonLog() throws {
        let sandbox = try Sandbox()
        for _ in 0..<2 {
            let run = try sandbox.run(["on", "--session", "noticed", "--pid", String(getpid())])
            #expect(run.exitStatus == 0)
        }
        let log = try String(contentsOf: sandbox.daemonLog, encoding: .utf8)
        #expect(log.components(separatedBy: AccountHome.foreignHomeMessage).count == 2)
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
        let accountHome = try #require(AccountHome.home())

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
        #expect(refusedHome == 0)
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

    @Test func aDaemonIsSpawnedFromTheRealFileBehindTheLinkOnPath() throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("agent-pet-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: base) }
        let executable = base.appendingPathComponent("AgentPet.app/Contents/MacOS/agent-pet", isDirectory: false)
        let link = base.appendingPathComponent("bin/agent-pet", isDirectory: false)
        try fileManager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: executable)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: executable)
        let real = executable.resolvingSymlinksInPath().path

        #expect(OwnExecutable.resolvedPath(mainBundleExecutablePath: link.path, invokedPath: nil) == real)
        #expect(OwnExecutable.resolvedPath(mainBundleExecutablePath: nil, invokedPath: link.path) == real)
        #expect(OwnExecutable.resolvedPath(mainBundleExecutablePath: executable.path, invokedPath: link.path) == real)
        #expect(OwnExecutable.resolvedPath(mainBundleExecutablePath: nil, invokedPath: nil) == nil)
    }
}
