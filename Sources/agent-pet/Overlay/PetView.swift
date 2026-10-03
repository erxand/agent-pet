import AgentPetCore
import AppKit

struct PetAppearance {
    let label: String
    let accent: AccentColor
    let mood: PetMood
    let message: String?
    let spriteSideLength: CGFloat

    func withResolvedLabel(_ resolvedLabel: String) -> PetAppearance {
        PetAppearance(
            label: resolvedLabel,
            accent: accent,
            mood: mood,
            message: message,
            spriteSideLength: spriteSideLength
        )
    }
}

protocol PetViewInteractionHandler: AnyObject {
    func petViewDidReceiveLeftClick(sessionId: String)
    func petViewDidReceiveRightClick(sessionId: String)
}

final class PetView: NSView {
    private static let redrawEpsilon: CGFloat = 0.01
    private static let boldMonospacedFontName = "Menlo-Bold"

    private static let labelFont = monospacedFont(
        ofSize: PetGeometry.labelFontSize,
        fallbackWeight: .bold
    )
    private static let bubbleFont = monospacedFont(
        ofSize: PetGeometry.bubbleFontSize,
        fallbackWeight: .black
    )

    let sessionId: String

    weak var interactionHandler: PetViewInteractionHandler?

    private(set) var petAppearance: PetAppearance
    private var spriteImage: NSImage?
    private var bubbleVerticalOffset: CGFloat = 0
    private var groundOffsetFraction: CGFloat = 1
    private var chromeOpacity: CGFloat = 0

    init(sessionId: String, petAppearance: PetAppearance) {
        self.sessionId = sessionId
        self.petAppearance = petAppearance
        super.init(frame: CGRect(origin: .zero, size: PetView.size(for: petAppearance)))
        toolTip = petAppearance.message
    }

    required init?(coder: NSCoder) {
        return nil
    }

    var preferredSize: CGSize {
        PetView.size(for: petAppearance)
    }

    func update(petAppearance: PetAppearance) {
        self.petAppearance = petAppearance
        toolTip = petAppearance.message
        needsDisplay = true
    }

    func update(resolvedLabel: String) {
        guard resolvedLabel != petAppearance.label else { return }
        petAppearance = petAppearance.withResolvedLabel(resolvedLabel)
        needsDisplay = true
    }

    func update(
        spriteImage: NSImage,
        bubbleVerticalOffset: CGFloat,
        groundOffsetFraction: CGFloat,
        chromeOpacity: CGFloat
    ) {
        let imageChanged = spriteImage !== self.spriteImage
        let bubbleOffsetChanged = PetView.differs(bubbleVerticalOffset, self.bubbleVerticalOffset)
        let groundOffsetChanged = PetView.differs(groundOffsetFraction, self.groundOffsetFraction)
        let chromeOpacityChanged = PetView.differs(chromeOpacity, self.chromeOpacity)
        self.spriteImage = spriteImage
        self.bubbleVerticalOffset = bubbleVerticalOffset
        self.groundOffsetFraction = groundOffsetFraction
        self.chromeOpacity = chromeOpacity
        if imageChanged || bubbleOffsetChanged || groundOffsetChanged || chromeOpacityChanged {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        drawSprite()
        drawChrome()
    }

    override func mouseDown(with event: NSEvent) {
        interactionHandler?.petViewDidReceiveLeftClick(sessionId: sessionId)
    }

    override func rightMouseDown(with event: NSEvent) {
        interactionHandler?.petViewDidReceiveRightClick(sessionId: sessionId)
    }

    static func size(for petAppearance: PetAppearance) -> CGSize {
        let pillWidth = labelPillWidth(for: petAppearance.label)
        return CGSize(
            width: ceil(max(petAppearance.spriteSideLength, pillWidth)),
            height: ceil(PetGeometry.totalHeight(spriteSideLength: petAppearance.spriteSideLength))
        )
    }

    private func drawSprite() {
        guard let spriteImage, let graphicsContext = NSGraphicsContext.current else { return }
        let sideLength = petAppearance.spriteSideLength
        let groundOffset = groundOffsetFraction
            * PetGeometry.submergedGroundOffset(spriteSideLength: sideLength)
        let spriteRect = CGRect(
            x: (bounds.width - sideLength) / 2,
            y: PetGeometry.spriteBaseline - groundOffset,
            width: sideLength,
            height: sideLength
        )
        guard spriteRect.maxY > bounds.minY else { return }
        graphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).setClip()
        spriteImage.draw(in: spriteRect, from: .zero, operation: .sourceOver, fraction: 1)
        graphicsContext.restoreGraphicsState()
    }

    private func drawChrome() {
        guard chromeOpacity > 0, let graphicsContext = NSGraphicsContext.current else { return }
        graphicsContext.saveGraphicsState()
        graphicsContext.cgContext.setAlpha(min(chromeOpacity, 1))
        drawLabelPill()
        if let bubbleSymbol = PetBubbleSymbol.forMood(petAppearance.mood) {
            drawBubble(symbol: bubbleSymbol)
        }
        graphicsContext.restoreGraphicsState()
    }

    private static func differs(_ candidate: CGFloat, _ current: CGFloat) -> Bool {
        abs(candidate - current) > redrawEpsilon
    }

    private func drawLabelPill() {
        let attributedLabel = PetView.attributedLabel(for: petAppearance.label)
        let labelSize = attributedLabel.size()
        let pillWidth = PetView.labelPillWidth(for: petAppearance.label)
        let pillRect = CGRect(
            x: (bounds.width - pillWidth) / 2,
            y: 0,
            width: pillWidth,
            height: PetGeometry.labelPillHeight
        )

        let pillPath = NSBezierPath(
            roundedRect: pillRect,
            xRadius: PetGeometry.labelPillHeight / 2,
            yRadius: PetGeometry.labelPillHeight / 2
        )
        PetGeometry.labelPillBackgroundColor.setFill()
        pillPath.fill()

        let dotRect = CGRect(
            x: pillRect.minX + PetGeometry.labelPillHorizontalPadding,
            y: pillRect.midY - PetGeometry.labelDotDiameter / 2,
            width: PetGeometry.labelDotDiameter,
            height: PetGeometry.labelDotDiameter
        )
        petAppearance.accent.color.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        attributedLabel.draw(
            at: CGPoint(
                x: dotRect.maxX + PetGeometry.labelDotTextGap,
                y: pillRect.midY - labelSize.height / 2
            )
        )
    }

    private func drawBubble(symbol: PetBubbleSymbol) {
        let bubbleBaseline = PetGeometry.labelPillHeight
            + PetGeometry.verticalGap
            + petAppearance.spriteSideLength
            + PetGeometry.verticalGap
        let bubbleRect = CGRect(
            x: (bounds.width - PetGeometry.bubbleSideLength) / 2,
            y: bubbleBaseline + bubbleVerticalOffset,
            width: PetGeometry.bubbleSideLength,
            height: PetGeometry.bubbleSideLength
        )
        let bubblePath = NSBezierPath(
            roundedRect: bubbleRect,
            xRadius: PetGeometry.bubbleCornerRadius,
            yRadius: PetGeometry.bubbleCornerRadius
        )
        petAppearance.accent.color.setFill()
        bubblePath.fill()
        SpritePalette.outline.setStroke()
        bubblePath.lineWidth = PetGeometry.bubbleBorderWidth
        bubblePath.stroke()

        let attributedSymbol = PetView.attributedBubbleSymbol(symbol)
        let symbolSize = attributedSymbol.size()
        attributedSymbol.draw(
            at: CGPoint(
                x: bubbleRect.midX - symbolSize.width / 2,
                y: bubbleRect.midY - symbolSize.height / 2
            )
        )
    }

    private static func labelPillWidth(for label: String) -> CGFloat {
        let labelWidth = attributedLabel(for: label).size().width
        return PetGeometry.labelPillHorizontalPadding * 2
            + PetGeometry.labelDotDiameter
            + PetGeometry.labelDotTextGap
            + labelWidth
    }

    private static func monospacedFont(ofSize fontSize: CGFloat, fallbackWeight: NSFont.Weight) -> NSFont {
        NSFont(name: boldMonospacedFontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: fallbackWeight)
    }

    private static func attributedLabel(for label: String) -> NSAttributedString {
        NSAttributedString(
            string: String(label.prefix(PetGeometry.labelCharacterLimit)),
            attributes: [
                .font: labelFont,
                .foregroundColor: PetGeometry.labelTextColor
            ]
        )
    }

    private static func attributedBubbleSymbol(_ symbol: PetBubbleSymbol) -> NSAttributedString {
        NSAttributedString(
            string: symbol.rawValue,
            attributes: [
                .font: bubbleFont,
                .foregroundColor: SpritePalette.outline
            ]
        )
    }
}
