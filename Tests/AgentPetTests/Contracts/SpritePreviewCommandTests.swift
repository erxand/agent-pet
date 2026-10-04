import Foundation
import Testing

@Suite("render and packs")
struct SpritePreviewCommandTests {
    private let escape = "\u{1B}["

    @Test func renderPrintsTwoPixelRowsPerLineInTruecolor() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("claude")
        let run = try sandbox.run(["render", "--pack", "claude"])

        #expect(run.exitStatus == 0)
        let lines = run.standardOutput.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        #expect(lines.count == 8)
        #expect(lines.allSatisfy { line in line.hasSuffix("\(escape)0m") })
        #expect(run.standardOutput.contains("\(escape)38;2;217;119;87m"))
        #expect(run.standardOutput.contains("\(escape)48;2;"))
        #expect(run.standardOutput.contains("\u{2580}"))
        let firstLine = String(lines[0]).replacingOccurrences(of: "\(escape)0m", with: "")
        #expect(firstLine == String(repeating: " ", count: 16))
    }

    @Test func renderFallsBackToTheBuiltInClaudeAndChoosesTheFrame() throws {
        let sandbox = try Sandbox()
        let builtIn = try sandbox.run(["render", "--pack", "claude"])
        #expect(builtIn.exitStatus == 0)
        #expect(builtIn.standardOutput.contains("\u{2580}"))

        try sandbox.installPack("golem")
        let first = try sandbox.run(["render", "--pack", "golem", "--animation", "walk", "--frame", "0"])
        let second = try sandbox.run(["render", "--pack", "golem", "--animation", "walk", "--frame", "1"])
        #expect(first.exitStatus == 0 && second.exitStatus == 0)
        #expect(first.standardOutput != second.standardOutput)
    }

    @Test func renderRejectsWhatItCannotDraw() throws {
        let sandbox = try Sandbox()
        #expect(try sandbox.run(["render"]).exitStatus == 2)
        #expect(try sandbox.run(["render", "--pack", "nosuch"]).standardError.contains("no sprite pack named nosuch"))
        #expect(try sandbox.run(["render", "--pack", "claude", "--animation", "fly"]).exitStatus == 2)
        #expect(try sandbox.run(["render", "--pack", "claude", "--frame", "99"]).exitStatus == 2)
    }

    @Test func packsListsAccentReservedAndLivePets() throws {
        let sandbox = try Sandbox()
        try "{\"reservedSprites\":[\"golem\"]}".write(
            to: sandbox.stateDirectory.appendingPathComponent("config.json"),
            atomically: true,
            encoding: .utf8
        )
        try sandbox.installPack("golem")
        try sandbox.installPack("nimbus")
        let livePid = "\(getpid())"
        try sandbox.run(["on", "--session", "owner", "--group", "dev", "--sprite", "golem", "--pid", livePid])
        try sandbox.run(["on", "--session", "helper", "--group", "dev", "--sprite", "nimbus", "--pid", livePid])
        try sandbox.run(["on", "--session", "solo", "--sprite", "nimbus", "--pid", livePid])
        try sandbox.run(["on", "--session", "gone", "--sprite", "nimbus", "--pid", "999999"])

        let run = try sandbox.run(["packs", "--json"])
        #expect(run.exitStatus == 0)
        let report = try #require(try JSONSerialization.jsonObject(with: Data(run.standardOutput.utf8)) as? [String: Any])
        let packs = try #require(report["packs"] as? [[String: Any]])
        #expect(packs.map { pack in pack["name"] as? String } == ["golem", "nimbus"])
        #expect(packs[0]["accent"] as? String == "green")
        #expect(packs[0]["reserved"] as? Bool == true)
        #expect(packs[0]["livePets"] as? Int == 1)
        #expect(packs[1]["accent"] as? String == "blue")
        #expect(packs[1]["reserved"] as? Bool == false)
        #expect(packs[1]["livePets"] as? Int == 1)

        let table = try sandbox.run(["packs"]).standardOutput.split(separator: "\n")
        #expect(table.count == 3)
        #expect(table[0].hasPrefix("PACK"))
        #expect(table[1].hasPrefix("golem") && table[1].contains("yes"))
    }
}
