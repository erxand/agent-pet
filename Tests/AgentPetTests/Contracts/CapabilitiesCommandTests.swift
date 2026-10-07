import Foundation
import Testing
@testable import AgentPetCore

@Suite("capabilities")
struct CapabilitiesCommandTests {
    @Test func printsOneWordPerLineForEveryCapability() throws {
        let sandbox = try Sandbox()
        let run = try sandbox.run(["capabilities"])

        #expect(run.exitStatus == 0)
        #expect(run.standardError.isEmpty)
        let words = run.standardOutput.split(separator: "\n").map { line in String(line) }
        #expect(words == AgentPetCapability.allCases.map { capability in capability.rawValue })
        #expect(words.contains("focus-target-select"))
        #expect(words.contains("hide-labels-floating"))
        #expect(words.allSatisfy { word in !word.contains(" ") })
    }

    @Test func touchesNoStateDirectory() throws {
        let sandbox = try Sandbox()
        try sandbox.run(["capabilities"])
        #expect(!sandbox.exists(sandbox.daemonLog))
        #expect(!sandbox.exists(sandbox.hookLog))
    }
}
