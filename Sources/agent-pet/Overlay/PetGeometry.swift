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
    static let labelCharacterLimit = 28
    static let labelPillBackgroundColor = NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 0.88)
    static let labelTextColor = NSColor.white

    static let bubbleSideLength: CGFloat = 22
    static let bubbleCornerRadius: CGFloat = 6
    static let bubbleBorderWidth: CGFloat = 2
    static let bubbleFontSize: CGFloat = 14
    static let bubbleBobAmplitude: CGFloat = 3
    static let bubbleBobRadiansPerSecond: Double = 4

    static let spriteBaseline: CGFloat = labelPillHeight + verticalGap

    static func spritePixelSideLength(frameSize: Int) -> CGFloat {
        CGFloat(frameSize * spriteScale)
    }

    static func submergedGroundOffset(spriteSideLength: CGFloat) -> CGFloat {
        spriteBaseline + spriteSideLength
    }

    static func totalHeight(spriteSideLength: CGFloat) -> CGFloat {
        spriteBaseline
            + spriteSideLength
            + verticalGap
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
}

struct OverlayScreenFrames {
    private static let fallbackFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    let visibleFrame: CGRect

    static func current() -> OverlayScreenFrames {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return OverlayScreenFrames(visibleFrame: fallbackFrame)
        }
        return OverlayScreenFrames(visibleFrame: screen.visibleFrame)
    }
}
