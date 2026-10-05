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

    static func homeHorizontalCenter(laneIndex: Int, laneCount: Int, screenFrame: CGRect) -> CGFloat {
        guard laneCount > 0 else { return screenFrame.midX }
        let fraction = CGFloat(laneIndex + 1) / CGFloat(laneCount + 1)
        return screenFrame.minX + screenFrame.width * fraction
    }

    /// Where a home on `oldFrame` lands on `newFrame`, at the same fraction of the width, so a
    /// pet that moves to another display keeps its lane.
    static func carriedHorizontalCenter(_ horizontalCenter: CGFloat, from oldFrame: CGRect, to newFrame: CGRect) -> CGFloat {
        guard oldFrame.width > 0 else { return newFrame.midX }
        let fraction = (horizontalCenter - oldFrame.minX) / oldFrame.width
        return newFrame.minX + newFrame.width * fraction
    }
}

struct OverlayScreenFrames {
    private static let fallbackFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    let visibleFrame: CGRect

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
            return OverlayScreenFrames(visibleFrame: fallbackFrame)
        }
        return OverlayScreenFrames(visibleFrame: screens[chosenIndex].visibleFrame)
    }
}
