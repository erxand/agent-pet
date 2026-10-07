import Foundation

package enum AgentPetCapability: String, CaseIterable {
    case focusTargetSelect = "focus-target-select"
}

enum CapabilitiesCommand {
    static func run() -> Int32 {
        for capability in AgentPetCapability.allCases {
            print(capability.rawValue)
        }
        return ExitCode.success
    }
}
