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
        "TICK-1140 (DEV)", "a very long session title that runs on", "x"
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

    private var nineLaneRoom: CGFloat {
        LaneLayout.maximumPetWidth(laneCount: 9, screenFrame: screens[0])
    }

    @Test func labelsThatDifferOnlyInTheirSuffixStillDifferWhenCut() {
        let pairs = [
            ("DEV SYSTEM T1", "DEV SYSTEM T2"),
            ("ZZTEST-1140 (RVW)", "ZZTEST-1140 (QA)"),
            ("a much longer project name 1a2b", "a much longer project name 3c4d")
        ]
        for placement in [LabelPlacement.pill, .nametag] {
            for (first, second) in pairs {
                let left = appearance(first, placement: placement).fitted(toWidth: nineLaneRoom).label
                let right = appearance(second, placement: placement).fitted(toWidth: nineLaneRoom).label
                #expect(left != right, "\(placement): \(left) vs \(right)")
                #expect(PetView.labelWidth(for: left, placement: placement) <= nineLaneRoom)
                if left != first { #expect(left.contains(LabelShortening.ellipsis)) }
            }
        }
        let cut = appearance("DEVELOPMENT SYSTEM T1", placement: .nametag).fitted(toWidth: 80).label
        #expect(cut.hasSuffix(" T1"))
        #expect(cut.contains(LabelShortening.ellipsis))
        let parenthesised = appearance("ZZTEST-1140 (RVW)", placement: .nametag).fitted(toWidth: 80).label
        #expect(parenthesised.hasSuffix(" (RVW)"))
    }

    @Test func aTrimmedLabelAlwaysShowsTheEllipsis() {
        let words = ["x", "short", "DEV SYSTEM T1", "ZZTEST-2 (QA)", "averyverylongsinglewordwithoutspaces",
                     "a very long session title that runs on", "trailing (unclosed"]
        for placement in [LabelPlacement.pill, .nametag] {
            for word in words {
                for width in stride(from: CGFloat(30), through: 260, by: 10) {
                    let fitted = appearance(word, placement: placement).fitted(toWidth: width).label
                    if fitted != word { #expect(fitted.contains(LabelShortening.ellipsis), "\(word) at \(width)") }
                }
            }
        }
        let middle = appearance("averyverylongsinglewordwithoutspaces", placement: .nametag).fitted(toWidth: 90).label
        #expect(middle.hasPrefix("a"))
        #expect(middle.hasSuffix("s"))
        #expect(PixelFont.canRender(middle))
    }

    @Test func movingToASmallerScreenRefitsTheNamesSoNeighboursStayApart() {
        let large = CGRect(x: 0, y: 0, width: 2560, height: 1415)
        let small = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let laneCount = 7
        let names = ["A LONG SESSION TITLE HERE", "ANOTHER LONG TITLE HERE"]
        let onLarge = names.map { name in
            appearance(name, placement: .nametag).fitted(toWidth: LaneLayout.maximumPetWidth(laneCount: laneCount, screenFrame: large))
        }
        let widestOnLarge = onLarge.map { look in PetView.size(for: look).width }.max() ?? 0
        let smallRoom = LaneLayout.maximumPetWidth(laneCount: laneCount, screenFrame: small)
        #expect(widestOnLarge > smallRoom + LaneLayout.neighbourPadding)
        let refitted = onLarge.map { look in
            appearance(names[onLarge.firstIndex { other in other.label == look.label } ?? 0], placement: .nametag)
                .fitted(toWidth: smallRoom)
        }
        let widths = refitted.map { look in PetView.size(for: look).width }
        let gap = LaneLayout.minimumGroundGap(widestPet: widths.max() ?? 0, laneCount: laneCount, screenFrame: small)
        let wander = LaneLayout.wanderHalfWidth(laneCount: laneCount, screenFrame: small, minimumGap: gap)
        let closest = LaneLayout.laneSpacing(laneCount: laneCount, screenFrame: small) - 2 * wander
        #expect((widths[0] + widths[1]) / 2 <= closest + 0.001)
    }

    @Test func numbersAtTheEndOfTheHeadSurviveTheCut() {
        let pairs = [
            ("TICK-1140 (DEV)", "TICK-1141 (DEV)"),
            ("TICK-1140 (RVW)", "TICK-1149 (RVW)"),
            ("PROJECT-REVIEW-1140 T1", "PROJECT-REVIEW-1141 T1")
        ]
        for laneCount in [9, 12] {
            let room = LaneLayout.maximumPetWidth(laneCount: laneCount, screenFrame: screens[0])
            for placement in [LabelPlacement.pill, .nametag] {
                for (first, second) in pairs {
                    let left = appearance(first, placement: placement).fitted(toWidth: room).label
                    let right = appearance(second, placement: placement).fitted(toWidth: room).label
                    #expect(left != right, "\(laneCount) lanes \(placement): \(left) vs \(right)")
                    #expect(PetView.labelWidth(for: left, placement: placement) <= room)
                    #expect(PetView.labelWidth(for: right, placement: placement) <= room)
                }
            }
        }
        let cut = appearance("TICK-1140 (DEV)", placement: .nametag).fitted(toWidth: 105).label
        #expect(cut.contains(LabelShortening.ellipsis))
        #expect(cut.hasSuffix("140 (DEV)"))
    }
}
