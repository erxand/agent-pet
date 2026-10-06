import Foundation
import Testing
@testable import AgentPetCore

@Suite("state commands")
struct StateCommandTests {
    private func states(_ sandbox: Sandbox) throws -> [String: [String: String]] {
        let run = try sandbox.run(["status", "--json"])
        let object = try #require(try JSONSerialization.jsonObject(with: Data(run.standardOutput.utf8)) as? [String: Any])
        return try #require(object["states"] as? [String: [String: String]])
    }

    private var commandsFile: (Sandbox) -> URL {
        { sandbox in sandbox.stateDirectory.appendingPathComponent("control/states.json") }
    }

    @Test func withNoCommandEveryStateIsItsDefaultAndStatusPrintsNoStatesLine() throws {
        let sandbox = try Sandbox()
        let reported = try states(sandbox)
        #expect(reported["physics"] == ["value": "ground", "source": "default"])
        #expect(reported["input"] == ["value": "on", "source": "default"])
        #expect(reported["visibility"] == ["value": "shown", "source": "default"])
        #expect(reported["level"] == ["value": "normal", "source": "default"])
        let text = try sandbox.run(["status"])
        #expect(!text.standardOutput.contains("states:"))
        #expect(!sandbox.exists(commandsFile(sandbox)))
    }

    @Test func eachCommandRoundTripsThroughStatusAndAutoHandsItBack() throws {
        let sandbox = try Sandbox()
        let float = try sandbox.run(["physics", "float"])
        #expect(float.exitStatus == 0)
        #expect(float.standardOutput == "physics: float\n")
        #expect(try sandbox.run(["input", "off"]).exitStatus == 0)
        #expect(try sandbox.run(["visibility", "hidden"]).exitStatus == 0)
        #expect(try sandbox.run(["level", "above", "com.example.app"]).exitStatus == 0)
        var reported = try states(sandbox)
        #expect(reported["physics"] == ["value": "float", "source": "cli"])
        #expect(reported["input"] == ["value": "off", "source": "cli"])
        #expect(reported["visibility"] == ["value": "hidden", "source": "cli"])
        #expect(reported["level"] == ["value": "above com.example.app", "source": "cli"])
        #expect(try sandbox.run(["status"]).standardOutput.contains("states: physics float (cli), input off (cli)"))

        #expect(try sandbox.run(["physics", "auto"]).standardOutput == "physics: auto\n")
        reported = try states(sandbox)
        #expect(reported["physics"] == ["value": "ground", "source": "default"])
        #expect(reported["input"] == ["value": "off", "source": "cli"])

        for kind in ["input", "visibility", "level"] {
            #expect(try sandbox.run([kind, "auto"]).exitStatus == 0)
        }
        #expect(!sandbox.exists(commandsFile(sandbox)))
        #expect(try states(sandbox)["level"] == ["value": "normal", "source": "default"])
    }

    @Test func badValuesAreUsageErrorsAndChangeNothing() throws {
        let sandbox = try Sandbox()
        for arguments in [["physics", "sideways"], ["physics"], ["input", "maybe"], ["level", "above"], ["level", "above", "a", "b"], ["visibility", "hidden", "now"], ["physics", "auto", "now"]] {
            let run = try sandbox.run(arguments)
            #expect(run.exitStatus == 2, "\(arguments)")
            #expect(run.standardError.contains("Valid values:"), "\(arguments)")
        }
        #expect(!sandbox.exists(commandsFile(sandbox)))
    }

    @Test func theCommandsFileIsWrittenWholeAndReadsBack() throws {
        let sandbox = try Sandbox()
        #expect(try sandbox.run(["level", "above", "com.example.app"]).exitStatus == 0)
        let payload = try Data(contentsOf: commandsFile(sandbox))
        let settings = try JSONDecoder().decode(PetStateSettings.self, from: payload)
        #expect(settings == PetStateSettings(level: .above(bundleIdentifier: "com.example.app")))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: commandsFile(sandbox).deletingLastPathComponent().path)
        #expect(leftovers == ["states.json"])
    }
}
