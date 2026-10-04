import Foundation
import Testing
@testable import AgentPetCore

@Suite("extra sprite directories")
struct SpriteDirectoriesTests {
    private let fileManager = FileManager.default

    private func extraFolder(in sandbox: Sandbox, named folderName: String = "extra-packs") throws -> URL {
        let folder = sandbox.home.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func copyShippedPack(_ packName: String, into folder: URL, as copyName: String? = nil) throws -> URL {
        let source = Sandbox.packageRoot.appendingPathComponent("sprites/\(packName)", isDirectory: true)
        let destination = folder.appendingPathComponent(copyName ?? packName, isDirectory: true)
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }

    private func writeConfig(_ json: String, in sandbox: Sandbox) throws {
        try json.write(to: sandbox.stateDirectory.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
    }

    private func packEntries(_ sandbox: Sandbox) throws -> [[String: Any]] {
        let run = try sandbox.run(["packs", "--json"])
        #expect(run.exitStatus == 0)
        let report = try #require(try JSONSerialization.jsonObject(with: Data(run.standardOutput.utf8)) as? [String: Any])
        return try #require(report["packs"] as? [[String: Any]])
    }

    @Test func theConfigKeyIsReadAndDefaultsToNoFolders() {
        #expect(AgentPetConfiguration.defaults.spriteDirectories.isEmpty)
        let configuration = ConfigurationFile.parse(Data(#"{"spriteDirectories":["~/protos", 7, "", "/abs/packs"]}"#.utf8))
        #expect(configuration.spriteDirectories == ["~/protos", "/abs/packs"])
    }

    @Test func packsInAnExtraFolderJoinPacksRenderAndTheRandomPool() throws {
        let sandbox = try Sandbox()
        let folder = try extraFolder(in: sandbox)
        try copyShippedPack("golem", into: folder, as: "proto")
        try writeConfig(#"{"spriteDirectories":["~/extra-packs"]}"#, in: sandbox)

        let entries = try packEntries(sandbox)
        #expect(entries.map { entry in entry["name"] as? String } == ["proto"])
        #expect(entries[0]["accent"] as? String == "green")

        let render = try sandbox.run(["render", "--pack", "proto"])
        #expect(render.exitStatus == 0)
        #expect(render.standardOutput.contains("\u{2580}"))

        let livePid = "\(getpid())"
        try sandbox.run(["on", "--session", "random", "--pid", livePid])
        #expect(sandbox.record("random")?["sprite"] as? String == "proto")
        #expect(sandbox.record("random")?["accent"] as? String == "green")
    }

    @Test func aReservedPackInAnExtraFolderIsLeftOutOfTheRandomPool() throws {
        let sandbox = try Sandbox()
        let folder = try extraFolder(in: sandbox)
        try copyShippedPack("golem", into: folder)
        try copyShippedPack("nimbus", into: folder)
        try writeConfig(#"{"spriteDirectories":["~/extra-packs"],"reservedSprites":["golem"]}"#, in: sandbox)

        let livePid = "\(getpid())"
        try sandbox.run(["on", "--session", "random", "--pid", livePid])
        #expect(sandbox.record("random")?["sprite"] as? String == "nimbus")
        try sandbox.run(["on", "--session", "chosen", "--sprite", "golem", "--pid", livePid])
        #expect(sandbox.record("chosen")?["accent"] as? String == "green")
    }

    @Test func anInstalledPackWinsANameClash() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        let folder = try extraFolder(in: sandbox)
        try copyShippedPack("nimbus", into: folder, as: "golem")
        try writeConfig(#"{"spriteDirectories":["~/extra-packs"]}"#, in: sandbox)

        let entries = try packEntries(sandbox)
        #expect(entries.map { entry in entry["name"] as? String } == ["golem"])
        #expect(entries[0]["accent"] as? String == "green")
    }

    @Test func aMissingFolderIsSkipped() throws {
        let sandbox = try Sandbox()
        let folder = try extraFolder(in: sandbox)
        try copyShippedPack("nimbus", into: folder)
        try writeConfig(#"{"spriteDirectories":["~/no-such-folder","relative/path","~/extra-packs"]}"#, in: sandbox)

        let entries = try packEntries(sandbox)
        #expect(entries.map { entry in entry["name"] as? String } == ["nimbus"])
    }

    @Test func theRegistryLogsEachFolderProblemOnceAndFollowsNewPacks() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        let folder = try extraFolder(in: sandbox)
        try copyShippedPack("nimbus", into: folder, as: "golem")
        let missing = sandbox.home.appendingPathComponent("gone").path
        let loader = SpritePackLoader(
            packsDirectory: sandbox.spritesDirectory,
            extraDirectoryPaths: [folder.path, missing],
            homeDirectory: sandbox.home
        )
        var logged: [String] = []
        let registry = SpritePackRegistry(loader: loader, reportFailure: { line in logged.append(line) })

        #expect(registry.reloadChangedPacks())
        #expect(!registry.reloadChangedPacks())
        #expect(logged.count == 2)
        #expect(logged.contains { line in line.contains("sprite pack golem in \(folder.path) is ignored") })
        #expect(logged.contains { line in line.contains("sprite directory \(missing) is missing or unreadable") })

        try copyShippedPack("tinowl", into: folder, as: "owlproto")
        #expect(registry.reloadChangedPacks())
        let owlCharacters = Set(registry.sheet(forPackNamed: "owlproto").colorsByCharacter.keys)
        let fallbackCharacters = Set(registry.sheet(forPackNamed: "nosuch").colorsByCharacter.keys)
        #expect(owlCharacters != fallbackCharacters)
        #expect(logged.count == 2)
    }
}
