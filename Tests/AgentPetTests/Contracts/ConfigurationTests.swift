import Foundation
import Testing
@testable import AgentPetCore

@Suite("config file")
struct ConfigurationTests {
    private func parse(_ json: String) -> AgentPetConfiguration {
        ConfigurationFile.parse(Data(json.utf8))
    }

    @Test func aMissingFileIsTheDefaults() throws {
        let directory = try TemporaryDirectory()
        let missing = directory.url.appendingPathComponent("config.json")
        #expect(ConfigurationFile.load(from: missing) == .defaults)
    }

    @Test func theDefaultsAreTodaysBehavior() {
        #expect(AgentPetConfiguration.defaults.focuser == .tmuxIterm)
        #expect(AgentPetConfiguration.defaults.sessionDirectoryPatterns == ["~/.claude/sessions"])
        #expect(AgentPetConfiguration.defaults.colorSync == .tmuxColor)
    }

    @Test func anEmptyObjectUnreadableJsonAndUnknownKeysAreTheDefaults() {
        #expect(parse("{}") == .defaults)
        #expect(parse("not json") == .defaults)
        #expect(parse("[1, 2]") == .defaults)
        #expect(parse(#"{"labelPlacement":"nametag","somethingNew":{"a":1}}"#) == .defaults)
    }

    @Test func everyKeyIsRead() {
        let configuration = parse("""
        {
          "focuser": { "kind": "command", "command": ["/abs/hq-pet-focus", "--flag"] },
          "sessionDirectories": ["~/.claude/sessions", "~/.claude-*/sessions"],
          "colorSync": "none"
        }
        """)
        #expect(configuration.focuser == .command(arguments: ["/abs/hq-pet-focus", "--flag"]))
        #expect(configuration.sessionDirectoryPatterns == ["~/.claude/sessions", "~/.claude-*/sessions"])
        #expect(configuration.colorSync == ColorSyncKind.none)
    }

    @Test func aBadValueFallsBackForThatKeyOnly() {
        let configuration = parse("""
        {
          "focuser": { "kind": "command" },
          "sessionDirectories": [3, "~/.claude-work/sessions"],
          "colorSync": "rainbow"
        }
        """)
        #expect(configuration.focuser == .tmuxIterm)
        #expect(configuration.sessionDirectoryPatterns == ["~/.claude-work/sessions"])
        #expect(configuration.colorSync == .tmuxColor)

        #expect(parse(#"{"focuser":{"kind":"teleport"}}"#).focuser == .tmuxIterm)
        #expect(parse(#"{"focuser":"command"}"#).focuser == .tmuxIterm)
        #expect(parse(#"{"sessionDirectories":[]}"#).sessionDirectoryPatterns == ["~/.claude/sessions"])
        #expect(parse(#"{"focuser":{"kind":"tmux-iterm"},"colorSync":"tmux-color"}"#) == .defaults)
    }

    @Test func agentPetConfigOverridesThePath() {
        let overridden = ConfigurationFile.path(environment: ["AGENT_PET_CONFIG": "/tmp/elsewhere.json"])
        #expect(overridden.path == "/tmp/elsewhere.json")
        let defaulted = ConfigurationFile.path(environment: ["AGENT_PET_CONFIG": ""])
        #expect(defaulted.lastPathComponent == "config.json")
        #expect(defaulted.deletingLastPathComponent().lastPathComponent == ".agent-pet")
    }

    @Test func theDefaultContractsAreTodaysImplementations() throws {
        let contracts = AgentPetContracts(configuration: .defaults, focusCompletion: .waits)
        #expect(contracts.focuser is TmuxItermFocuser)
        #expect(contracts.colorSync is TmuxPromptBarColorSync)
        #expect(contracts.spriteStrategy is LeastUsedSpriteStrategy)
        #expect(contracts.grouping is OnePetPerSessionGrouping)
        #expect(contracts.sessionSource is DirectorySessionSource)

        let home = try TemporaryDirectory()
        let source = DirectorySessionSource(patterns: AgentPetConfiguration.defaults.sessionDirectoryPatterns, homeDirectory: home.url)
        #expect(source.directories().map { directory in directory.path } == [home.url.appendingPathComponent(".claude/sessions").path])
    }

    @Test func theAddedContractsAreChosenByConfig() {
        let configuration = AgentPetConfiguration(
            focuser: .command(arguments: ["/bin/true"]),
            sessionDirectoryPatterns: ["~/.claude/sessions"],
            colorSync: .none
        )
        let contracts = AgentPetContracts(configuration: configuration, focusCompletion: .detaches)
        #expect(contracts.focuser is CommandFocuser)
        #expect(contracts.colorSync is DisabledColorSync)
    }
}
