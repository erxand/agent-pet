import Foundation
import Testing
@testable import AgentPetCore

@Suite("packs iCloud has not downloaded")
struct DatalessPackTests {
    private final class Residency {
        var datalessPaths: Set<String> = []
        var requestedPaths: [String] = []

        func mark(_ fileURL: URL) { datalessPaths.insert(fileURL.standardizedFileURL.path) }
        func clear() { datalessPaths.removeAll() }

        var fileResidency: FileResidency {
            FileResidency(
                isDataless: { [unowned self] fileURL in datalessPaths.contains(fileURL.standardizedFileURL.path) },
                requestDownload: { [unowned self] fileURL in requestedPaths.append(fileURL.standardizedFileURL.path) }
            )
        }
    }

    private final class Reports {
        var lines: [String] = []
        func notDownloaded(_ packName: String) -> [String] {
            lines.filter { line in line.contains("sprite pack \(packName) is not downloaded yet") }
        }
    }

    private func registry(for sandbox: Sandbox, residency: Residency, reports: Reports) -> SpritePackRegistry {
        let loader = SpritePackLoader(
            packsDirectory: sandbox.spritesDirectory,
            extraDirectoryPaths: [],
            homeDirectory: sandbox.home,
            residency: residency.fileResidency
        )
        return SpritePackRegistry(loader: loader, reportFailure: { line in reports.lines.append(line) })
    }

    private func packFile(_ sandbox: Sandbox, pack packName: String, file fileName: String) -> URL {
        sandbox.spritesDirectory.appendingPathComponent(packName, isDirectory: true).appendingPathComponent(fileName)
    }

    @Test func theDaemonSkipsAPackWithAnEvictedFileAndLoadsItOnceTheFileIsLocal() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        let residency = Residency()
        let reports = Reports()
        let idle = packFile(sandbox, pack: "golem", file: "idle.txt")
        residency.mark(idle)
        let registry = registry(for: sandbox, residency: residency, reports: reports)

        #expect(registry.reloadChangedPacks() == false)
        #expect(registry.ownAccent(forPackNamed: "golem") == nil)
        #expect(registry.reloadChangedPacks() == false)
        #expect(reports.notDownloaded("golem").count == 1)
        #expect(residency.requestedPaths == [idle.standardizedFileURL.path])

        residency.clear()
        #expect(registry.reloadChangedPacks() == true)
        #expect(registry.ownAccent(forPackNamed: "golem") == .green)
        #expect(registry.reloadChangedPacks() == false)

        residency.mark(idle)
        #expect(registry.reloadChangedPacks() == false)
        #expect(registry.ownAccent(forPackNamed: "golem") == .green)
        #expect(reports.notDownloaded("golem").count == 1)
    }

    @Test func aPendingPackLoadsOnceItsFlagClearsEvenWithNoFileSystemEvent() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        try sandbox.installPack("seon")
        let residency = Residency()
        let reports = Reports()
        let idle = packFile(sandbox, pack: "golem", file: "idle.txt")
        residency.mark(idle)
        var askedAbout: [String] = []
        let loader = SpritePackLoader(
            packsDirectory: sandbox.spritesDirectory,
            extraDirectoryPaths: [],
            homeDirectory: sandbox.home,
            residency: FileResidency(isDataless: { fileURL in
                askedAbout.append(fileURL.standardizedFileURL.path)
                return residency.datalessPaths.contains(fileURL.standardizedFileURL.path)
            })
        )
        let registry = SpritePackRegistry(loader: loader, reportFailure: { line in reports.lines.append(line) })
        var gate = RescanGate(fallbackIntervalInSeconds: 5)
        let firstScan = gate.shouldRescan(changeReported: false, forced: true, now: 0)
        #expect(firstScan)
        _ = registry.reloadChangedPacks()
        #expect(registry.hasPendingDownloads)
        #expect(registry.ownAccent(forPackNamed: "seon") == .yellow)
        #expect(registry.ownAccent(forPackNamed: "golem") == nil)

        askedAbout.removeAll()
        #expect(!registry.pendingDownloadBecameLocal())
        let golemDirectory = sandbox.spritesDirectory.appendingPathComponent("golem", isDirectory: true).standardizedFileURL.path
        #expect(!askedAbout.isEmpty)
        #expect(askedAbout.allSatisfy { path in path.hasPrefix(golemDirectory) })
        let quietTick = gate.shouldRescan(changeReported: false, forced: false, now: 0.3)
        #expect(!quietTick)

        residency.clear()
        let becameLocal = registry.hasPendingDownloads && registry.pendingDownloadBecameLocal()
        #expect(becameLocal)
        let pendingTick = gate.shouldRescan(changeReported: becameLocal, forced: false, now: 0.6)
        #expect(pendingTick)
        #expect(registry.reloadChangedPacks())
        #expect(registry.ownAccent(forPackNamed: "golem") == .green)
        #expect(!registry.hasPendingDownloads)
    }

    @Test func anEvictedPackDirectoryIsNeverLookedInside() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        let residency = Residency()
        let packDirectory = sandbox.spritesDirectory.appendingPathComponent("golem", isDirectory: true)
        residency.mark(packDirectory)
        var askedAbout: [String] = []
        let loader = SpritePackLoader(
            packsDirectory: sandbox.spritesDirectory,
            extraDirectoryPaths: [],
            homeDirectory: sandbox.home,
            residency: FileResidency(isDataless: { fileURL in
                askedAbout.append(fileURL.lastPathComponent)
                return residency.datalessPaths.contains(fileURL.standardizedFileURL.path)
            })
        )

        guard case .notDownloaded(let undownloaded) = loader.load(packDirectory: packDirectory) else {
            Issue.record("expected the pack to be reported as not downloaded")
            return
        }
        #expect(undownloaded.map { fileURL in fileURL.standardizedFileURL.path } == [packDirectory.standardizedFileURL.path])
        #expect(askedAbout == ["golem"])
    }

    @Test func anEvictedSpriteDirectoryIsNotListedAndKeepsThePacksAlreadyLoaded() throws {
        let sandbox = try Sandbox()
        let folder = sandbox.home.appendingPathComponent("cloud-packs", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: Sandbox.packageRoot.appendingPathComponent("sprites/golem", isDirectory: true),
            to: folder.appendingPathComponent("golem", isDirectory: true)
        )
        let residency = Residency()
        let reports = Reports()
        let loader = SpritePackLoader(
            packsDirectory: sandbox.spritesDirectory,
            extraDirectoryPaths: ["~/cloud-packs"],
            homeDirectory: sandbox.home,
            residency: residency.fileResidency
        )
        let registry = SpritePackRegistry(loader: loader, reportFailure: { line in reports.lines.append(line) })
        #expect(registry.reloadChangedPacks() == true)
        #expect(registry.ownAccent(forPackNamed: "golem") == .green)

        residency.mark(folder)
        #expect(loader.scan().directoryByPackName["golem"] == nil)
        #expect(registry.reloadChangedPacks() == false)
        #expect(registry.reloadChangedPacks() == false)
        #expect(registry.ownAccent(forPackNamed: "golem") == .green)
        #expect(reports.lines.filter { line in line.contains("~/cloud-packs is not downloaded yet") }.count == 1)
        #expect(residency.requestedPaths == [folder.standardizedFileURL.path])

        residency.clear()
        #expect(registry.reloadChangedPacks() == false)
        #expect(registry.ownAccent(forPackNamed: "golem") == .green)
    }

    @Test func theRealFlagReaderSaysAnOrdinaryFileIsLocal() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        #expect(FileResidency.hasDatalessFlag(packFile(sandbox, pack: "golem", file: "pack.json")) == false)
        #expect(FileResidency.hasDatalessFlag(packFile(sandbox, pack: "golem", file: "missing.txt")) == false)
    }

    private func simulated(_ fileURLs: [URL]) -> [String: String] {
        [EnvironmentVariableName.simulatedDatalessPaths: fileURLs.map { fileURL in fileURL.path }.joined(separator: ":")]
    }

    @Test func packsMarksAnUndownloadedPackInTextAndJson() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        try sandbox.installPack("nimbus")
        let environment = simulated([packFile(sandbox, pack: "golem", file: "pack.json")])

        let json = try sandbox.run(["packs", "--json"], environment: environment)
        #expect(json.exitStatus == 0)
        let report = try #require(try JSONSerialization.jsonObject(with: Data(json.standardOutput.utf8)) as? [String: Any])
        let entries = try #require(report["packs"] as? [[String: Any]])
        let golem = try #require(entries.first { entry in entry["name"] as? String == "golem" })
        let nimbus = try #require(entries.first { entry in entry["name"] as? String == "nimbus" })
        #expect(golem["downloaded"] as? Bool == false)
        #expect(golem["accent"] is NSNull)
        #expect(golem["reserved"] as? Bool == false)
        #expect(golem["livePets"] as? Int == 0)
        #expect(nimbus["downloaded"] as? Bool == true)
        #expect(nimbus["accent"] as? String != nil)

        let text = try sandbox.run(["packs"], environment: environment)
        #expect(text.exitStatus == 0)
        let golemLine = try #require(text.standardOutput.split(separator: "\n").first { line in line.hasPrefix("golem") })
        let nimbusLine = try #require(text.standardOutput.split(separator: "\n").first { line in line.hasPrefix("nimbus") })
        #expect(golemLine.contains("not downloaded"))
        #expect(!nimbusLine.contains("not downloaded"))
    }

    @Test func onWithAnUndownloadedPackEnrollsWithNoAccent() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        let environment = simulated([packFile(sandbox, pack: "golem", file: "walk.txt")])

        let run = try sandbox.run(
            ["on", "--session", "cloud", "--sprite", "golem", "--pid", "\(getpid())", "--no-color-sync"],
            environment: environment
        )
        #expect(run.exitStatus == 0)
        #expect(sandbox.record("cloud")?["sprite"] as? String == "golem")
        #expect(sandbox.record("cloud")?["accent"] == nil)

        try sandbox.run(["on", "--session", "local", "--sprite", "golem", "--pid", "\(getpid())", "--no-color-sync"])
        #expect(sandbox.record("local")?["accent"] as? String == "green")
    }

    @Test func renderOfAnUndownloadedPackFailsAndSaysWhy() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        let environment = simulated([sandbox.spritesDirectory.appendingPathComponent("golem", isDirectory: true)])

        let run = try sandbox.run(["render", "--pack", "golem"], environment: environment)
        #expect(run.exitStatus == 1)
        #expect(run.standardOutput.isEmpty)
        #expect(run.standardError.contains("sprite pack golem is not downloaded yet"))

        let local = try sandbox.run(["render", "--pack", "golem"])
        #expect(local.exitStatus == 0)
    }
}
