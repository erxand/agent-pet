import AgentPetCore
import AppKit

enum PetGeometry {
    static let spriteScale = 4
    static let verticalGap: CGFloat = 3
    static let windowBottomInset: CGFloat = 4

    static let labelPillHeight: CGFloat = 18
    static let labelPillHorizontalPadding: CGFloat = 8
    static let labelDotDiameter: CGFloat = 6
    static let labelDotTextGap: CGFloat = 4
    static let labelFontSize: CGFloat = 10
    static let labelCharacterLimit = PetLabel.displayCharacterLimit
    static let labelPillBackgroundColor = NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 0.88)
    static let labelTextColor = NSColor.white

    static let nametagPixelScale: CGFloat = 2
    static let nametagHorizontalPadding: CGFloat = 5
    static let nametagVerticalPadding: CGFloat = 3
    static let nametagAccentStripeHeight: CGFloat = 2
    static let nametagFallbackFontSize: CGFloat = 9
    static let nametagHeight: CGFloat = CGFloat(PixelFont.glyphHeight) * nametagPixelScale
        + nametagVerticalPadding * 2
        + nametagAccentStripeHeight

    static let bubbleSideLength: CGFloat = 22
    static let bubbleCaptionPadding: CGFloat = 6
    static let bubbleCaptionGap: CGFloat = 4
    static let bubbleCornerRadius: CGFloat = 6
    static let bubbleBorderWidth: CGFloat = 2
    static let bubbleFontSize: CGFloat = 14
    static let bubbleBobAmplitude: CGFloat = 3
    static let bubbleBobRadiansPerSecond: Double = 4

    static func spriteBaseline(labelPlacement: LabelPlacement) -> CGFloat {
        switch labelPlacement {
        case .pill: return labelPillHeight + verticalGap
        case .nametag: return verticalGap
        }
    }

    static func spritePixelSideLength(frameSize: Int) -> CGFloat {
        CGFloat(frameSize * spriteScale)
    }

    static func submergedGroundOffset(spriteSideLength: CGFloat, labelPlacement: LabelPlacement) -> CGFloat {
        spriteBaseline(labelPlacement: labelPlacement) + spriteSideLength
    }

    static func nametagBaseline(spriteSideLength: CGFloat) -> CGFloat {
        spriteBaseline(labelPlacement: .nametag) + spriteSideLength + verticalGap
    }

    static func bubbleBaseline(spriteSideLength: CGFloat, labelPlacement: LabelPlacement) -> CGFloat {
        switch labelPlacement {
        case .pill:
            return spriteBaseline(labelPlacement: .pill) + spriteSideLength + verticalGap
        case .nametag:
            return nametagBaseline(spriteSideLength: spriteSideLength) + nametagHeight + verticalGap
        }
    }

    static func totalHeight(spriteSideLength: CGFloat, labelPlacement: LabelPlacement) -> CGFloat {
        bubbleBaseline(spriteSideLength: spriteSideLength, labelPlacement: labelPlacement)
            + bubbleSideLength
            + bubbleBobAmplitude
    }
}

enum PetBubbleSymbol: String {
    case attention = "!"
    case question = "?"

    static func forMood(_ mood: PetMood) -> PetBubbleSymbol? {
        switch mood {
        case .ready: return nil
        case .needsInput: return .attention
        case .blocked: return .question
        }
    }
}

enum LaneLayout {
    static let wanderHalfWidth: CGFloat = 120
    static let bodyWidthFraction: CGFloat = 0.6
    static let laneSpacingFraction: CGFloat = 0.9

    private struct PlacedPet {
        let index: Int
        let center: CGFloat
    }

    static func laneCenters(count: Int, screenFrame: CGRect) -> [CGFloat] {
        (0..<count).map { laneIndex in
            homeHorizontalCenter(laneIndex: laneIndex, laneCount: count, screenFrame: screenFrame)
        }
    }

    static let neighbourPadding: CGFloat = 8

    static func laneSpacing(laneCount: Int, screenFrame: CGRect) -> CGFloat {
        screenFrame.width / CGFloat(max(laneCount, 1) + 1)
    }

    static func minimumGroundGap(widestPet: CGFloat, laneCount: Int, screenFrame: CGRect) -> CGFloat {
        min(widestPet + neighbourPadding, laneSpacing(laneCount: laneCount, screenFrame: screenFrame) * laneSpacingFraction)
    }

    static func maximumPetWidth(laneCount: Int, screenFrame: CGRect) -> CGFloat {
        laneSpacing(laneCount: laneCount, screenFrame: screenFrame) * laneSpacingFraction - neighbourPadding
    }

    static func allowsStep(from current: CGFloat, to next: CGFloat, neighbour: CGFloat, minimumGap: CGFloat) -> Bool {
        let side = current - neighbour
        if side != 0 && (next - neighbour) * side <= 0 { return false }
        let nextDistance = abs(next - neighbour)
        return !(nextDistance < minimumGap && nextDistance < abs(side))
    }

    static func wanderHalfWidth(laneCount: Int, screenFrame: CGRect, minimumGap: CGFloat) -> CGFloat {
        let spacing = laneSpacing(laneCount: laneCount, screenFrame: screenFrame)
        return min(wanderHalfWidth, max(0, (spacing - minimumGap) / 2))
    }

    static func assignedLanes(currentCenters: [CGFloat?], laneCenters: [CGFloat]) -> [Int] {
        var placed: [PlacedPet] = []
        for (index, center) in currentCenters.enumerated() {
            guard let center else { continue }
            placed.append(PlacedPet(index: index, center: center))
        }
        placed.sort { left, right in
            left.center == right.center ? left.index < right.index : left.center < right.center
        }
        let laneCount = laneCenters.count
        guard placed.count <= laneCount else { return Array(0..<currentCenters.count) }
        let unreachable = CGFloat.greatestFiniteMagnitude
        var cost = Array(repeating: Array(repeating: unreachable, count: laneCount + 1), count: placed.count + 1)
        var tookLane = Array(repeating: Array(repeating: false, count: laneCount + 1), count: placed.count + 1)
        for lane in 0...laneCount { cost[0][lane] = 0 }
        for pet in stride(from: 1, through: placed.count, by: 1) {
            for lane in stride(from: pet, through: laneCount, by: 1) {
                let skipping: CGFloat = cost[pet][lane - 1]
                let distance: CGFloat = abs(placed[pet - 1].center - laneCenters[lane - 1])
                let taking: CGFloat = cost[pet - 1][lane - 1] + distance
                if taking <= skipping {
                    cost[pet][lane] = taking
                    tookLane[pet][lane] = true
                } else {
                    cost[pet][lane] = skipping
                }
            }
        }
        var lanes = Array(repeating: -1, count: currentCenters.count)
        var usedLanes = Set<Int>()
        var pet = placed.count
        var lane = laneCount
        while pet > 0 {
            if tookLane[pet][lane] {
                lanes[placed[pet - 1].index] = lane - 1
                usedLanes.insert(lane - 1)
                pet -= 1
            }
            lane -= 1
        }
        var freeLanes = (0..<laneCount).filter { lane in !usedLanes.contains(lane) }.makeIterator()
        for index in lanes.indices where lanes[index] < 0 {
            lanes[index] = freeLanes.next() ?? index
        }
        return lanes
    }

    static func homeHorizontalCenter(laneIndex: Int, laneCount: Int, screenFrame: CGRect) -> CGFloat {
        guard laneCount > 0 else { return screenFrame.midX }
        let fraction = CGFloat(laneIndex + 1) / CGFloat(laneCount + 1)
        return screenFrame.minX + screenFrame.width * fraction
    }

    static func carriedHorizontalCenter(_ horizontalCenter: CGFloat, from oldFrame: CGRect, to newFrame: CGRect) -> CGFloat {
        guard oldFrame.width > 0 else { return newFrame.midX }
        let fraction = (horizontalCenter - oldFrame.minX) / oldFrame.width
        return newFrame.minX + newFrame.width * fraction
    }
}

struct OverlayScreenFrames {
    private static let fallbackFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    let visibleFrame: CGRect
    let screenFrame: CGRect

    static func current(chooser: DisplayChooser) -> OverlayScreenFrames {
        let screens = NSScreen.screens
        let focusedIndex = NSScreen.main.flatMap { mainScreen in
            screens.firstIndex { screen in screen === mainScreen }
        }
        let displays = AttachedDisplays(
            names: screens.map { screen in screen.localizedName },
            focusedIndex: focusedIndex
        )
        guard let chosenIndex = chooser.chosenIndex(among: displays) else {
            return OverlayScreenFrames(visibleFrame: fallbackFrame, screenFrame: fallbackFrame)
        }
        let screen = screens[chosenIndex]
        return OverlayScreenFrames(visibleFrame: screen.visibleFrame, screenFrame: screen.frame)
    }
}
