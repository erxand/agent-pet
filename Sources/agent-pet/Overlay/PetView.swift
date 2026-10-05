import AgentPetCore
import AppKit

struct PetAppearance {
    let label: String
    let accent: AccentColor
    let mood: PetMood
    let message: String?
    let bubbleCaption: String?
    let labelPlacement: LabelPlacement
    let spriteSideLength: CGFloat

    func withResolvedLabel(_ resolvedLabel: String) -> PetAppearance {
        PetAppearance(
            label: resolvedLabel,
            accent: accent,
            mood: mood,
            message: message,
            bubbleCaption: bubbleCaption,
            labelPlacement: labelPlacement,
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
    private static let clickTargetColor = NSColor(calibratedWhite: 0, alpha: 0.01)
    private static let boldMonospacedFontName = "Menlo-Bold"

    private static let labelFont = monospacedFont(
        ofSize: PetGeometry.labelFontSize,
        fallbackWeight: .bold
    )
    private static let bubbleFont = monospacedFont(
        ofSize: PetGeometry.bubbleFontSize,
        fallbackWeight: .black
    )
    private static let nametagFallbackFont = monospacedFont(
        ofSize: PetGeometry.nametagFallbackFontSize,
        fallbackWeight: .bold
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        interactionHandler?.petViewDidReceiveLeftClick(sessionId: sessionId)
    }

    override func rightMouseDown(with event: NSEvent) {
        interactionHandler?.petViewDidReceiveRightClick(sessionId: sessionId)
    }

    static func size(for petAppearance: PetAppearance) -> CGSize {
        let labelWidth: CGFloat
        switch petAppearance.labelPlacement {
        case .pill: labelWidth = labelPillWidth(for: petAppearance.label)
        case .nametag: labelWidth = nametagWidth(for: petAppearance.label)
        }
        let bubbleWidth = bubbleWidth(symbol: PetBubbleSymbol.forMood(petAppearance.mood), caption: petAppearance.bubbleCaption)
        return CGSize(
            width: ceil(max(petAppearance.spriteSideLength, labelWidth, bubbleWidth)),
            height: ceil(PetGeometry.totalHeight(
                spriteSideLength: petAppearance.spriteSideLength,
                labelPlacement: petAppearance.labelPlacement
            ))
        )
    }

    private func drawSprite() {
        guard let spriteImage, let graphicsContext = NSGraphicsContext.current else { return }
        let sideLength = petAppearance.spriteSideLength
        let groundOffset = groundOffsetFraction
            * PetGeometry.submergedGroundOffset(spriteSideLength: sideLength, labelPlacement: petAppearance.labelPlacement)
        let spriteRect = CGRect(
            x: (bounds.width - sideLength) / 2,
            y: PetGeometry.spriteBaseline(labelPlacement: petAppearance.labelPlacement) - groundOffset,
            width: sideLength,
            height: sideLength
        )
        guard spriteRect.maxY > bounds.minY else { return }
        graphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).setClip()
        PetView.clickTargetColor.setFill()
        spriteRect.intersection(bounds).fill()
        spriteImage.draw(in: spriteRect, from: .zero, operation: .sourceOver, fraction: 1)
        graphicsContext.restoreGraphicsState()
    }

    private func drawChrome() {
        guard chromeOpacity > 0, let graphicsContext = NSGraphicsContext.current else { return }
        graphicsContext.saveGraphicsState()
        graphicsContext.cgContext.setAlpha(min(chromeOpacity, 1))
        switch petAppearance.labelPlacement {
        case .pill: drawLabelPill()
        case .nametag: drawNametag()
        }
        let bubbleSymbol = PetBubbleSymbol.forMood(petAppearance.mood)
        if bubbleSymbol != nil || petAppearance.bubbleCaption != nil {
            drawBubble(symbol: bubbleSymbol, caption: petAppearance.bubbleCaption)
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

    private func drawNametag() {
        let label = PetView.clippedLabel(petAppearance.label)
        let tagWidth = PetView.nametagWidth(for: label)
        let tagRect = CGRect(
            x: ((bounds.width - tagWidth) / 2).rounded(),
            y: PetGeometry.nametagBaseline(spriteSideLength: petAppearance.spriteSideLength),
            width: tagWidth,
            height: PetGeometry.nametagHeight
        )
        PetGeometry.labelPillBackgroundColor.setFill()
        tagRect.fill()
        petAppearance.accent.color.setFill()
        CGRect(x: tagRect.minX, y: tagRect.minY, width: tagRect.width, height: PetGeometry.nametagAccentStripeHeight).fill()

        let textOrigin = CGPoint(
            x: tagRect.minX + PetGeometry.nametagHorizontalPadding,
            y: tagRect.minY + PetGeometry.nametagAccentStripeHeight + PetGeometry.nametagVerticalPadding
        )
        guard let glyphRows = PixelFont.rows(for: label) else {
            drawFallbackNametagText(label, origin: textOrigin)
            return
        }
        PetGeometry.labelTextColor.setFill()
        let pixelSide = PetGeometry.nametagPixelScale
        for (rowIndex, row) in glyphRows.enumerated() {
            let rowY = textOrigin.y + CGFloat(glyphRows.count - 1 - rowIndex) * pixelSide
            for (columnIndex, character) in row.enumerated() where PixelFont.isInk(character) {
                CGRect(x: textOrigin.x + CGFloat(columnIndex) * pixelSide, y: rowY, width: pixelSide, height: pixelSide).fill()
            }
        }
    }

    private func drawFallbackNametagText(_ label: String, origin: CGPoint) {
        guard let graphicsContext = NSGraphicsContext.current else { return }
        let attributedText = PetView.attributedNametagFallback(for: label)
        let textHeight = CGFloat(PixelFont.glyphHeight) * PetGeometry.nametagPixelScale
        graphicsContext.saveGraphicsState()
        graphicsContext.shouldAntialias = false
        attributedText.draw(at: CGPoint(x: origin.x, y: origin.y + (textHeight - attributedText.size().height) / 2))
        graphicsContext.restoreGraphicsState()
    }

    private func drawBubble(symbol: PetBubbleSymbol?, caption: String?) {
        let bubbleBaseline = PetGeometry.bubbleBaseline(
            spriteSideLength: petAppearance.spriteSideLength,
            labelPlacement: petAppearance.labelPlacement
        )
        let bubbleWidth = PetView.bubbleWidth(symbol: symbol, caption: caption)
        let bubbleRect = CGRect(
            x: (bounds.width - bubbleWidth) / 2,
            y: bubbleBaseline + bubbleVerticalOffset,
            width: bubbleWidth,
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

        guard let caption else {
            guard let symbol else { return }
            let attributedSymbol = PetView.attributedBubbleSymbol(symbol)
            let symbolSize = attributedSymbol.size()
            attributedSymbol.draw(
                at: CGPoint(
                    x: bubbleRect.midX - symbolSize.width / 2,
                    y: bubbleRect.midY - symbolSize.height / 2
                )
            )
            return
        }
        var cursor = bubbleRect.minX + PetGeometry.bubbleCaptionPadding
        if let symbol {
            let attributedSymbol = PetView.attributedBubbleSymbol(symbol)
            let symbolSize = attributedSymbol.size()
            attributedSymbol.draw(at: CGPoint(x: cursor, y: bubbleRect.midY - symbolSize.height / 2))
            cursor += symbolSize.width + PetGeometry.bubbleCaptionGap
        }
        let attributedCaption = PetView.attributedCaption(caption)
        attributedCaption.draw(at: CGPoint(x: cursor, y: bubbleRect.midY - attributedCaption.size().height / 2))
    }

    private static func bubbleWidth(symbol: PetBubbleSymbol?, caption: String?) -> CGFloat {
        guard let caption else { return PetGeometry.bubbleSideLength }
        var contentWidth = attributedCaption(caption).size().width
        if let symbol {
            contentWidth += attributedBubbleSymbol(symbol).size().width + PetGeometry.bubbleCaptionGap
        }
        return max(PetGeometry.bubbleSideLength, contentWidth + PetGeometry.bubbleCaptionPadding * 2)
    }

    private static func clippedLabel(_ label: String) -> String {
        String(label.prefix(PetGeometry.labelCharacterLimit))
    }

    private static func nametagWidth(for label: String) -> CGFloat {
        let clipped = clippedLabel(label)
        let textWidth = PixelFont.canRender(clipped)
            ? CGFloat(PixelFont.width(of: clipped)) * PetGeometry.nametagPixelScale
            : ceil(attributedNametagFallback(for: clipped).size().width)
        return textWidth + PetGeometry.nametagHorizontalPadding * 2
    }

    private static func attributedNametagFallback(for label: String) -> NSAttributedString {
        NSAttributedString(
            string: label,
            attributes: [
                .font: nametagFallbackFont,
                .foregroundColor: PetGeometry.labelTextColor
            ]
        )
    }

    private static func attributedCaption(_ caption: String) -> NSAttributedString {
        NSAttributedString(
            string: clippedLabel(caption),
            attributes: [
                .font: labelFont,
                .foregroundColor: SpritePalette.outline
            ]
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
