import Foundation

package enum AgentPetCapability: String, CaseIterable {
    case focusTargetSelect = "focus-target-select"
    case groupModeLead = "group-mode-lead"
    case disambiguator = "disambiguator"
    case hideLabelsFloating = "hide-labels-floating"
    case dockGround = "dock-ground"
    case groundGap = "ground-gap"
}

enum CapabilitiesCommand {
    static func run() -> Int32 {
        for capability in AgentPetCapability.allCases {
            print(capability.rawValue)
        }
        return ExitCode.success
    }
}
