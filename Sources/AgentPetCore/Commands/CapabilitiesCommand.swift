import Foundation

package enum AgentPetCapability: String, CaseIterable {
    case focusTargetSelect = "focus-target-select"
    case hideLabelsFloating = "hide-labels-floating"
}

enum CapabilitiesCommand {
    static func run() -> Int32 {
        for capability in AgentPetCapability.allCases {
            print(capability.rawValue)
        }
        return ExitCode.success
    }
}
