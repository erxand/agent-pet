import Foundation

package enum AgentPetCapability: String, CaseIterable {
    case releaseGrace = "release-grace"
    case focusHold = "focus-hold"
    case leadFocusHold = "lead-focus-hold"
    case focusTargetSelect = "focus-target-select"
    case groupModeLead = "group-mode-lead"
    case disambiguator = "disambiguator"
    case hideLabelsFloating = "hide-labels-floating"
    case dockGround = "dock-ground"
}

enum CapabilitiesCommand {
    static func run() -> Int32 {
        for capability in AgentPetCapability.allCases {
            print(capability.rawValue)
        }
        return ExitCode.success
    }
}
