import AppKit
import Foundation
import Testing
import AgentPetCore
@testable import agent_pet

@Suite("the names of pets standing side by side never overlap")
@MainActor
struct NeighbourLabelTests {
    private let screens = [
        CGRect(x: 0, y: 0, width: 1440, height: 900),
        CGRect(x: 0, y: 0, width: 1728, height: 1117),
        CGRect(x: 0, y: 0, width: 2560, height: 1415)
    ]
    private let labels = [
        "ZZTEST-1 (RVW)", "ZZTEST-2 (QA)", "DEV SYSTEM T1", "DEV SYSTEM T2",
        "NIST-1140 (DEV)", "a very long session title that runs on", "x"
    ]

    private func appearance(_ label: String, placement: LabelPlacement, caption: String? = nil) -> PetAppearance {
        PetAppearance(
            label: label, accent: .cyan, mood: caption == nil ? .ready : .needsInput, message: nil,
            bubbleCaption: caption, labelPlacement: placement, spriteSideLength: 128
        )
    }

    @Test func neighboursAtTheEndsOfTheirWanderKeepTheirNamesApart() {
        for screen in screens {
            for placement in [LabelPlacement.pill, .nametag] {
                for laneCount in 2...9 {
                    let room = LaneLayout.maximumPetWidth(laneCount: laneCount, screenFrame: screen)
                    let widths = labels.map { label in
                        PetView.size(for: appearance(label, placement: placement).fitted(toWidth: room)).width
                    }
                    let widest = widths.max() ?? 0
                    let gap = LaneLayout.minimumGroundGap(widestPet: widest, laneCount: laneCount, screenFrame: screen)
                    let wander = LaneLayout.wanderHalfWidth(laneCount: laneCount, screenFrame: screen, minimumGap: gap)
                    let closest = LaneLayout.laneSpacing(laneCount: laneCount, screenFrame: screen) - 2 * wander
                    guard widest > 128 else { continue }
                    #expect(closest >= widest + 0.001 - LaneLayout.neighbourPadding)
                    for (left, right) in zip(widths, widths.dropFirst()) {
                        #expect((left + right) / 2 <= closest + 0.001, "\(placement) \(laneCount) lanes on \(screen.width)")
                    }
                }
            }
        }
    }

    @Test func aNameThatDoesNotFitItsLaneIsTrimmedAndOneThatFitsIsLeftAlone() {
        let shortName = appearance("ZZTEST-2 (QA)", placement: .nametag)
        #expect(shortName.fitted(toWidth: 400).label == "ZZTEST-2 (QA)")
        let long = appearance("a very long session title that runs on", placement: .pill, caption: "a long bubble caption here")
        let fitted = long.fitted(toWidth: 120)
        #expect(fitted.label.count < 28)
        #expect(!fitted.label.hasSuffix(" "))
        #expect(PetView.labelWidth(for: fitted.label, placement: .pill) <= 120)
        #expect(PetView.size(for: fitted).width <= 128)
    }

    @Test func theStepCheckKeepsTwoRealNamesApart() {
        let screen = screens[1]
        let laneCount = 6
        let room = LaneLayout.maximumPetWidth(laneCount: laneCount, screenFrame: screen)
        let left = PetView.size(for: appearance("ZZTEST-1 (RVW)", placement: .nametag).fitted(toWidth: room)).width
        let right = PetView.size(for: appearance("ZZTEST-2 (QA)", placement: .nametag).fitted(toWidth: room)).width
        let gap = LaneLayout.minimumGroundGap(widestPet: max(left, right), laneCount: laneCount, screenFrame: screen)
        var leftCenter: CGFloat = 400
        let rightCenter: CGFloat = 400 + gap + 5
        while LaneLayout.allowsStep(from: leftCenter, to: leftCenter + 1, neighbour: rightCenter, minimumGap: gap) {
            leftCenter += 1
        }
        #expect(rightCenter - leftCenter >= (left + right) / 2)
    }
}
