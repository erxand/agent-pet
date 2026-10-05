import AppKit
import Foundation
import Testing
@testable import AgentPetCore

@Suite("accent on the sprite")
struct SpriteAccentTintTests {
    private let escape = "\u{1B}["

    private func registry(for sandbox: Sandbox) -> SpritePackRegistry {
        let loader = SpritePackLoader(
            packsDirectory: sandbox.spritesDirectory,
            extraDirectoryPaths: [],
            homeDirectory: sandbox.home
        )
        let registry = SpritePackRegistry(loader: loader, reportFailure: { _ in })
        _ = registry.reloadChangedPacks()
        return registry
    }

    private func hex(_ color: NSColor?) -> String? {
        TerminalSpriteRenderer.color(color).map { color in "\(color.red),\(color.green),\(color.blue)" }
    }

    private func writePack(named packName: String, manifest: String, in sandbox: Sandbox) throws {
        let source = Sandbox.packageRoot.appendingPathComponent("sprites/mossling", isDirectory: true)
        let destination = sandbox.spritesDirectory.appendingPathComponent(packName, isDirectory: true)
        try FileManager.default.copyItem(at: source, to: destination)
        try manifest.write(to: destination.appendingPathComponent("pack.json"), atomically: true, encoding: .utf8)
    }

    @Test func aChosenAccentPaintsTheAccentInksAndTheirShade() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("mossling")
        let registry = registry(for: sandbox)
        let own = registry.sheet(forPackNamed: "mossling").colorsByCharacter

        let tinted = registry.sheet(forPackNamed: "mossling", chosenAccent: .blue)
        #expect(tinted.tint == .blue)
        #expect(hex(tinted.sheet.colorsByCharacter["A"]) == "76,141,255")
        #expect(hex(tinted.sheet.colorsByCharacter["a"]) == "52,96,173")
        for (character, color) in own where character != "A" && character != "a" {
            #expect(hex(tinted.sheet.colorsByCharacter[character]) == hex(color))
        }

        let again = registry.sheet(forPackNamed: "mossling", chosenAccent: .blue)
        #expect(hex(again.sheet.colorsByCharacter["A"]) == "76,141,255")
        #expect(registry.sheet(forPackNamed: "mossling", chosenAccent: nil).tint == nil)
    }

    @Test func aPackWithoutAccentInksKeepsItsPalette() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("claude")
        try writePack(
            named: "badinks",
            manifest: ##"{"name":"badinks","palette":{"#":"#22301A","g":"#6FA845","A":"#D9453D"},"accentInks":{"accent":"Z","shade":"a"}}"##,
            in: sandbox
        )
        let registry = registry(for: sandbox)

        for packName in ["claude", "badinks", "nosuch"] {
            let session = registry.sheet(forPackNamed: packName, chosenAccent: .purple)
            #expect(session.tint == nil)
            #expect(hex(session.sheet.colorsByCharacter["A"]) == hex(registry.sheet(forPackNamed: packName).colorsByCharacter["A"]))
        }
    }

    @Test func anAccentFilledFromThePackKeepsThePalette() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("mossling")
        let livePid = "\(getpid())"
        try sandbox.run(["on", "--session", "filled", "--sprite", "mossling", "--pid", livePid])
        try sandbox.run(["on", "--session", "chosen", "--sprite", "mossling", "--accent", "red", "--pid", livePid])

        let filled = try #require(sandbox.record("filled"))
        #expect(filled["accent"] as? String == "red")
        #expect(filled["accentFromPack"] as? Bool == true)
        let chosen = try #require(sandbox.record("chosen"))
        #expect(chosen["accent"] as? String == "red")
        #expect(chosen["accentFromPack"] as? Bool == false)

        try sandbox.run(["on", "--session", "filled", "--accent", "cyan", "--pid", livePid])
        let rechosen = try #require(sandbox.record("filled"))
        #expect(rechosen["accent"] as? String == "cyan")
        #expect(rechosen["accentFromPack"] as? Bool == false)

        let decoder = JSONDecoder()
        let packFilled = try decoder.decode(
            PetSession.self,
            from: Data(#"{"sessionId":"x","accent":"red","accentFromPack":true}"#.utf8)
        )
        let registry = registry(for: sandbox)
        let packAccent = registry.ownAccent(forPackNamed: "mossling")
        #expect(packAccent == .red)
        #expect(packFilled.chosenAccent(packAccent: packAccent) == nil)
        #expect(packFilled.resolvedAccent == .red)
        let chosenRed = try decoder.decode(
            PetSession.self,
            from: Data(#"{"sessionId":"z","accent":"red","accentFromPack":false}"#.utf8)
        )
        #expect(chosenRed.chosenAccent(packAccent: packAccent) == .red)
        #expect(registry.sheet(forPackNamed: "mossling", chosenAccent: packFilled.chosenAccent(packAccent: packAccent)).tint == nil)
        #expect(registry.sheet(forPackNamed: "mossling", chosenAccent: chosenRed.chosenAccent(packAccent: packAccent)).tint == .red)
    }

    @Test func aRecordFromBeforeTheFlagKeepsThePacksPalette() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        let registry = registry(for: sandbox)
        let packAccent = try #require(registry.ownAccent(forPackNamed: "golem"))
        let decoder = JSONDecoder()
        let copied = try decoder.decode(
            PetSession.self,
            from: Data(#"{"sessionId":"old","sprite":"golem","accent":"\#(packAccent.rawValue)"}"#.utf8)
        )
        #expect(copied.chosenAccent(packAccent: packAccent) == nil)
        let other: AccentColor = packAccent == .blue ? .red : .blue
        let chosen = try decoder.decode(
            PetSession.self,
            from: Data(#"{"sessionId":"old","sprite":"golem","accent":"\#(other.rawValue)"}"#.utf8)
        )
        #expect(chosen.chosenAccent(packAccent: packAccent) == other)
    }

    @Test func accentInksIsOffUnlessTheConfigTurnsItOn() {
        #expect(!AgentPetConfiguration.defaults.paintsAccentInks)
        #expect(ConfigurationFile.parse(Data(#"{"accentInks":true}"#.utf8)).paintsAccentInks)
        #expect(!ConfigurationFile.parse(Data(#"{"accentInks":1}"#.utf8)).paintsAccentInks)
    }

    @Test func renderPreviewsAnAccent() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        try sandbox.installPack("claude")
        let red = "\(escape)38;2;255;82;82m"
        let redShade = "2;173;56;56m"

        let plain = try sandbox.run(["render", "--pack", "golem"])
        let tinted = try sandbox.run(["render", "--pack", "golem", "--accent", "red"])
        #expect(plain.exitStatus == 0 && tinted.exitStatus == 0)
        #expect(!plain.standardOutput.contains("255;82;82m"))
        #expect(tinted.standardOutput.contains(red) || tinted.standardOutput.contains("\(escape)48;2;255;82;82m"))
        #expect(tinted.standardOutput.contains(redShade))

        let claudePlain = try sandbox.run(["render", "--pack", "claude"])
        let claudeTinted = try sandbox.run(["render", "--pack", "claude", "--accent", "red"])
        #expect(claudeTinted.exitStatus == 0)
        #expect(claudeTinted.standardOutput == claudePlain.standardOutput)

        let unknown = try sandbox.run(["render", "--pack", "golem", "--accent", "teal"])
        #expect(unknown.exitStatus == 2)
        #expect(unknown.standardError.contains("unknown accent teal"))
    }
}
