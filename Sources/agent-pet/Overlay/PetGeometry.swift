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
        spriteBaseline(layout: LabelLayout(placement: labelPlacement))
    }

    static func spriteBaseline(layout: LabelLayout) -> CGFloat {
        if layout.labelUnderFeet { return labelPillHeight + verticalGap }
        return layout.feetFlush ? 0 : verticalGap
    }

    static func spritePixelSideLength(frameSize: Int) -> CGFloat {
        CGFloat(frameSize * spriteScale)
    }

    static func submergedGroundOffset(spriteSideLength: CGFloat, layout: LabelLayout) -> CGFloat {
        spriteBaseline(layout: layout) + spriteSideLength
    }

    static func labelOverHeadBaseline(spriteSideLength: CGFloat, layout: LabelLayout) -> CGFloat {
        spriteBaseline(layout: layout) + spriteSideLength + verticalGap
    }

    static func bubbleBaseline(spriteSideLength: CGFloat, layout: LabelLayout) -> CGFloat {
        guard !layout.labelUnderFeet else {
            return spriteBaseline(layout: layout) + spriteSideLength + verticalGap
        }
        let labelHeight: CGFloat
        switch layout.placement {
        case .pill: labelHeight = labelPillHeight
        case .nametag: labelHeight = nametagHeight
        }
        return labelOverHeadBaseline(spriteSideLength: spriteSideLength, layout: layout) + labelHeight + verticalGap
    }

    static func totalHeight(spriteSideLength: CGFloat, labelPlacement: LabelPlacement) -> CGFloat {
        totalHeight(spriteSideLength: spriteSideLength, layout: LabelLayout(placement: labelPlacement))
    }

    static func totalHeight(spriteSideLength: CGFloat, layout: LabelLayout) -> CGFloat {
        bubbleBaseline(spriteSideLength: spriteSideLength, layout: layout)
            + bubbleSideLength
            + bubbleBobAmplitude
    }
}

protocol LaneWalker: AnyObject {
    var homeHorizontalCenter: CGFloat { get set }
    var animator: PetAnimator { get }
    var laneWidth: CGFloat { get }
    var windowWidth: CGFloat { get }
    var isInFlight: Bool { get }
}

enum LaneRedivision {
    static func apply(
        to everyWalker: [LaneWalker],
        keepingStanding everyStanding: [Bool],
        screenFrame: CGRect
    ) -> CGFloat {
        let grounded = zip(everyWalker, everyStanding).filter { walker, _ in !walker.isInFlight }
        let walkers = grounded.map { walker, _ in walker }
        let standing = grounded.map { _, keeps in keeps }
        let laneCenters = LaneLayout.laneCenters(count: walkers.count, screenFrame: screenFrame)
        let lanes = LaneLayout.assignedLanes(
            currentCenters: zip(walkers, standing).map { walker, keeps in
                keeps ? walker.homeHorizontalCenter + walker.animator.horizontalOffsetFromHome : nil
            },
            laneCenters: laneCenters
        )
        let widestPet = walkers.map { walker in walker.laneWidth }.max() ?? 0
        let minimumGap = LaneLayout.minimumGroundGap(widestPet: widestPet, laneCount: walkers.count, screenFrame: screenFrame)
        let wanderHalfWidth = LaneLayout.wanderHalfWidth(laneCount: walkers.count, screenFrame: screenFrame, minimumGap: minimumGap)
        for ((walker, keeps), lane) in zip(zip(walkers, standing), lanes) {
            let home = laneCenters[lane]
            if keeps { walker.animator.moveHome(by: home - walker.homeHorizontalCenter) }
            walker.homeHorizontalCenter = home
            walker.animator.limitWander(to: wanderHalfWidth)
        }
        return minimumGap
    }

    static func carry(_ walker: LaneWalker, from oldFrame: CGRect, to newFrame: CGRect) {
        guard !walker.isInFlight else {
            walker.homeHorizontalCenter = LaneLayout.carriedHorizontalCenter(walker.homeHorizontalCenter, from: oldFrame, to: newFrame)
            return
        }
        let standing = LaneLayout.carriedStandingCenter(
            walker.homeHorizontalCenter + walker.animator.horizontalOffsetFromHome,
            from: oldFrame,
            to: newFrame,
            windowWidth: walker.windowWidth
        )
        walker.homeHorizontalCenter = LaneLayout.carriedHorizontalCenter(walker.homeHorizontalCenter, from: oldFrame, to: newFrame)
        walker.animator.stand(atHorizontalOffsetFromHome: standing - walker.homeHorizontalCenter)
    }
}

struct LabelLayout: Equatable {
    let placement: LabelPlacement
    let feetFlush: Bool

    init(placement: LabelPlacement, feetFlush: Bool = false) {
        self.placement = placement
        self.feetFlush = feetFlush
    }

    var labelUnderFeet: Bool {
        switch placement {
        case .pill: return !feetFlush
        case .nametag: return false
        }
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
    static let initialWanderHalfWidth: CGFloat = 120
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
        screenFrame.width / CGFloat(max(laneCount, 1))
    }

    static func lane(index laneIndex: Int, laneCount: Int, screenFrame: CGRect) -> ClosedRange<CGFloat> {
        let width = laneSpacing(laneCount: laneCount, screenFrame: screenFrame)
        let start = screenFrame.minX + width * CGFloat(laneIndex)
        return start...(start + width)
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
        return max(0, (spacing - minimumGap) / 2)
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
        let slice = lane(index: laneIndex, laneCount: laneCount, screenFrame: screenFrame)
        return (slice.lowerBound + slice.upperBound) / 2
    }

    static func carriedStandingCenter(
        _ standingCenter: CGFloat,
        from oldFrame: CGRect,
        to newFrame: CGRect,
        windowWidth: CGFloat
    ) -> CGFloat {
        let carried = carriedHorizontalCenter(standingCenter, from: oldFrame, to: newFrame)
        let halfWindow = min(windowWidth, newFrame.width) / 2
        return min(max(carried, newFrame.minX + halfWindow), newFrame.maxX - halfWindow)
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

enum PetChrome {
    static func shownOpacity(_ opacity: Double, spaceMotion: SpaceMotion?, hidesLabelsWhileFloating: Bool) -> Double {
        guard hidesLabelsWhileFloating, let spaceMotion, !spaceMotion.isOnGround else { return opacity }
        return 0
    }
}
