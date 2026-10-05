import Foundation
import Testing
@testable import AgentPetCore

@Suite("the display pets live on")
struct DisplayChooserTests {
    private static let laptop = "Built-in Retina Display"
    private static let monitor = "LG UltraFine"
    private static let projector = "Epson Projector"

    private func displays(focusedIndex: Int?) -> AttachedDisplays {
        AttachedDisplays(
            names: [DisplayChooserTests.monitor, DisplayChooserTests.laptop, DisplayChooserTests.projector],
            focusedIndex: focusedIndex
        )
    }

    private let noDisplays = AttachedDisplays(names: [], focusedIndex: nil)

    @Test func focusedFollowsKeyboardFocusLikeToday() {
        let chooser = FocusedDisplayChooser()
        #expect(chooser.chosenIndex(among: displays(focusedIndex: 2)) == 2)
        #expect(chooser.chosenIndex(among: displays(focusedIndex: 1)) == 1)
    }

    @Test func focusedFallsBackToTheFirstDisplayLikeToday() {
        let chooser = FocusedDisplayChooser()
        #expect(chooser.chosenIndex(among: displays(focusedIndex: nil)) == 0)
        #expect(chooser.chosenIndex(among: displays(focusedIndex: 7)) == 0)
        #expect(chooser.chosenIndex(among: noDisplays) == nil)
    }

    @Test func primaryIgnoresKeyboardFocus() {
        let chooser = PrimaryDisplayChooser()
        #expect(chooser.chosenIndex(among: displays(focusedIndex: 2)) == 0)
        #expect(chooser.chosenIndex(among: displays(focusedIndex: nil)) == 0)
        #expect(chooser.chosenIndex(among: noDisplays) == nil)
    }

    @Test func primaryFollowsMacOSWhenThePrimaryChanges() {
        let lidClosed = AttachedDisplays(names: [DisplayChooserTests.monitor], focusedIndex: 0)
        let lidOpenLaptopPrimary = AttachedDisplays(
            names: [DisplayChooserTests.laptop, DisplayChooserTests.monitor],
            focusedIndex: 1
        )
        let chooser = PrimaryDisplayChooser()
        #expect(chooser.chosenIndex(among: lidClosed).map { index in lidClosed.names[index] } == DisplayChooserTests.monitor)
        #expect(
            chooser.chosenIndex(among: lidOpenLaptopPrimary).map { index in lidOpenLaptopPrimary.names[index] }
                == DisplayChooserTests.laptop
        )
    }

    @Test func aNamedDisplayIsFoundByItsName() {
        let chooser = NamedDisplayChooser(displayName: DisplayChooserTests.projector)
        #expect(chooser.chosenIndex(among: displays(focusedIndex: 1)) == 2)
    }

    @Test func aNamedDisplayThatIsNotAttachedFallsBackToPrimary() {
        let chooser = NamedDisplayChooser(displayName: "Sidecar iPad")
        #expect(chooser.chosenIndex(among: displays(focusedIndex: 2)) == 0)
        #expect(chooser.chosenIndex(among: noDisplays) == nil)
    }

    @Test func theConfigValuesAreRead() {
        #expect(DisplayChoice(configValue: "focused") == .focused)
        #expect(DisplayChoice(configValue: "primary") == .primary)
        #expect(DisplayChoice(configValue: "name:LG UltraFine") == .named("LG UltraFine"))
        #expect(DisplayChoice(configValue: "name:name:odd") == .named("name:odd"))
    }

    @Test func anUnknownValueIsNotAChoice() {
        #expect(DisplayChoice(configValue: "name:") == nil)
        #expect(DisplayChoice(configValue: "Primary") == nil)
        #expect(DisplayChoice(configValue: "left") == nil)
        #expect(DisplayChoice(configValue: "") == nil)
    }

    @Test func theConfigChoosesTheChooser() {
        func chooser(for json: String) -> DisplayChooser {
            AgentPetContracts(configuration: ConfigurationFile.parse(Data(json.utf8)), focusCompletion: .waits).displayChooser
        }
        #expect(chooser(for: "{}") is FocusedDisplayChooser)
        #expect(chooser(for: #"{"display":"primary"}"#) is PrimaryDisplayChooser)
        #expect((chooser(for: #"{"display":"name:LG UltraFine"}"#) as? NamedDisplayChooser)?.displayName == "LG UltraFine")
        #expect(chooser(for: #"{"display":"elsewhere"}"#) is FocusedDisplayChooser)
        #expect(chooser(for: #"{"display":3}"#) is FocusedDisplayChooser)
    }
}
