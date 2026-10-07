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

}

extension PetAppearance {
    func fitted(toWidth maximumWidth: CGFloat) -> PetAppearance {
        let fittedLabel = PetAppearance.shortened(label) { text in
            text.count <= PetGeometry.labelCharacterLimit
                && PetView.labelWidth(for: text, placement: labelPlacement) <= maximumWidth
        }
        let symbol = PetBubbleSymbol.forMood(mood)
        let fittedCaption = bubbleCaption.map { caption in
            PetAppearance.shortened(caption) { text in
                text.count <= PetGeometry.labelCharacterLimit
                    && PetView.bubbleWidth(symbol: symbol, caption: text) <= maximumWidth
            }
        }
        guard fittedLabel != label || fittedCaption != bubbleCaption else { return self }
        return PetAppearance(
            label: fittedLabel,
            accent: accent,
            mood: mood,
            message: message,
            bubbleCaption: fittedCaption,
            labelPlacement: labelPlacement,
            spriteSideLength: spriteSideLength
        )
    }
}

enum LabelShortening {
    static let ellipsis = "\u{2026}"
    private static let longestSuffixWord = 6

    static func shortened(_ text: String, fits: (String) -> Bool) -> String {
        guard !fits(text) else { return text }
        if let (head, suffix) = splitDistinguishingSuffix(text),
           let kept = longestFit(upTo: head.count, fits: { count in fits(headCut(head, keeping: count) + suffix) }) {
            return headCut(head, keeping: kept) + suffix
        }
        let characters = Array(text)
        let kept = longestFit(upTo: characters.count - 1) { count in fits(middleCut(characters, keeping: count)) } ?? 0
        return middleCut(characters, keeping: kept)
    }

    static func splitDistinguishingSuffix(_ text: String) -> (head: String, suffix: String)? {
        if text.hasSuffix(")"), let open = text.lastIndex(of: "("), open > text.startIndex {
            var head = String(text[..<open])
            let separator = head.hasSuffix(" ") ? " " : ""
            while head.last == " " { head.removeLast() }
            guard !head.isEmpty else { return nil }
            return (head, separator + String(text[open...]))
        }
        guard let space = text.lastIndex(of: " ") else { return nil }
        let word = text[text.index(after: space)...]
        let head = String(text[..<space])
        guard !word.isEmpty, word.count <= longestSuffixWord,
              !head.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return (head, String(text[space...]))
    }

    private static func headCut(_ head: String, keeping count: Int) -> String {
        var kept = String(head.prefix(count))
        while kept.last == " " { kept.removeLast() }
        return kept + ellipsis
    }

    private static func middleCut(_ characters: [Character], keeping count: Int) -> String {
        let front = (count + 1) / 2
        var head = String(characters.prefix(front))
        while head.last == " " { head.removeLast() }
        var tail = String(characters.suffix(count - front))
        while tail.first == " " { tail.removeFirst() }
        return head + ellipsis + tail
    }

    private static func longestFit(upTo maximum: Int, fits: (Int) -> Bool) -> Int? {
        guard maximum >= 0, fits(0) else { return nil }
        var low = 0
        var high = maximum
        while low < high {
            let middle = (low + high + 1) / 2
            if fits(middle) { low = middle } else { high = middle - 1 }
        }
        return low
    }
}

extension PetAppearance {
    fileprivate static func shortened(_ text: String, fits: (String) -> Bool) -> String {
        LabelShortening.shortened(text, fits: fits)
    }
}

protocol PetViewInteractionHandler: AnyObject {
    func petViewDidReceiveLeftClick(sessionId: String)
    func petViewDidReceiveRightClick(sessionId: String)
}

final class PetView: NSView {
    private static let redrawEpsilon: CGFloat = 0.01
    private static let fallbackBackingScale: CGFloat = 2
    private static let degreesPerRadian: CGFloat = 180 / .pi
    static let clickTargetColor = NSColor(calibratedWhite: 0, alpha: 0.01)
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
    private(set) var chromeOpacity: CGFloat = 0
    private(set) var spaceRotationInRadians: CGFloat?

    var isInert = false {
        didSet {
            guard isInert != oldValue else { return }
            toolTip = isInert ? nil : petAppearance.message
        }
    }

    private let contentView = NSView()
    private let spriteView = PetSpriteView()
    private let labelView = PetChromePartView(part: .label)
    private let bubbleView = PetChromePartView(part: .bubble)

    init(sessionId: String, petAppearance: PetAppearance) {
        self.sessionId = sessionId
        self.petAppearance = petAppearance
        super.init(frame: CGRect(origin: .zero, size: PetView.size(for: petAppearance)))
        toolTip = petAppearance.message
        wantsLayer = true
        contentView.clipsToBounds = true
        for partView in [labelView, bubbleView] {
            partView.owner = self
        }
        contentView.addSubview(spriteView)
        contentView.addSubview(labelView)
        contentView.addSubview(bubbleView)
        addSubview(contentView)
        for drawnView in [labelView, bubbleView] {
            drawnView.layer?.contentsFormat = .RGBA8Uint
        }
        layoutParts()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    var preferredSize: CGSize {
        let contentSize = PetView.size(for: petAppearance)
        guard spaceRotationInRadians != nil else { return contentSize }
        let side = ceil(hypot(contentSize.width, contentSize.height))
        return CGSize(width: side, height: side)
    }

    var contentSize: CGSize {
        PetView.size(for: petAppearance)
    }

    private var contentBounds: CGRect {
        CGRect(origin: .zero, size: contentSize)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutParts()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isInert else { return nil }
        return super.hitTest(point) == nil ? nil : self
    }

    func update(spaceRotationInRadians rotation: CGFloat?) {
        guard rotation != spaceRotationInRadians else { return }
        spaceRotationInRadians = rotation
        layoutParts()
    }

    func update(petAppearance: PetAppearance) {
        self.petAppearance = petAppearance
        toolTip = isInert ? nil : petAppearance.message
        redrawChrome()
        layoutParts()
    }

    func update(
        spriteImage: NSImage,
        bubbleVerticalOffset: CGFloat,
        groundOffsetFraction: CGFloat,
        chromeOpacity: CGFloat
    ) {
        let snappedBubbleOffset = snappedToDevicePixels(bubbleVerticalOffset)
        let bubbleOffsetChanged = drawsBubble && PetView.differs(snappedBubbleOffset, self.bubbleVerticalOffset)
        let groundOffsetChanged = PetView.differs(groundOffsetFraction, self.groundOffsetFraction)
        let chromeOpacityChanged = PetView.differs(chromeOpacity, self.chromeOpacity)
        if spriteImage !== self.spriteImage {
            spriteView.image = spriteImage
        }
        self.spriteImage = spriteImage
        self.bubbleVerticalOffset = snappedBubbleOffset
        self.groundOffsetFraction = groundOffsetFraction
        self.chromeOpacity = chromeOpacity
        if chromeOpacityChanged {
            redrawChrome()
        }
        if bubbleOffsetChanged || groundOffsetChanged || chromeOpacityChanged {
            layoutParts()
        }
    }

    private var drawsBubble: Bool {
        chromeOpacity > 0 && (PetBubbleSymbol.forMood(petAppearance.mood) != nil || petAppearance.bubbleCaption != nil)
    }

    private func snappedToDevicePixels(_ offset: CGFloat) -> CGFloat {
        let scale = window?.backingScaleFactor ?? PetView.fallbackBackingScale
        return (offset * scale).rounded() / scale
    }

    func drawSpriteWithCoreGraphics() {
        spriteView.drawsThroughLayerContents = false
    }

    private func redrawChrome() {
        labelView.needsDisplay = true
        bubbleView.needsDisplay = true
    }

    private func layoutParts() {
        let content = contentBounds
        let rotationInDegrees = (spaceRotationInRadians ?? 0) * PetView.degreesPerRadian
        contentView.frameCenterRotation = 0
        contentView.frame = CGRect(
            x: (bounds.width - content.width) / 2,
            y: (bounds.height - content.height) / 2,
            width: content.width,
            height: content.height
        )
        contentView.frameCenterRotation = rotationInDegrees
        let sideLength = petAppearance.spriteSideLength
        let groundOffset = groundOffsetFraction
            * PetGeometry.submergedGroundOffset(spriteSideLength: sideLength, labelPlacement: petAppearance.labelPlacement)
        spriteView.frame = CGRect(
            x: (content.width - sideLength) / 2,
            y: PetGeometry.spriteBaseline(labelPlacement: petAppearance.labelPlacement) - groundOffset,
            width: sideLength,
            height: sideLength
        )
        spriteView.isHidden = spriteView.frame.maxY <= content.minY
        labelView.frame = content
        bubbleView.frame = content.offsetBy(dx: 0, dy: bubbleVerticalOffset)
        labelView.isHidden = chromeOpacity <= 0
        bubbleView.isHidden = !drawsBubble
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        !isInert
    }

    override func mouseDown(with event: NSEvent) {
        guard !isInert else { return }
        interactionHandler?.petViewDidReceiveLeftClick(sessionId: sessionId)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard !isInert else { return }
        interactionHandler?.petViewDidReceiveRightClick(sessionId: sessionId)
    }

    static func labelWidth(for label: String, placement: LabelPlacement) -> CGFloat {
        switch placement {
        case .pill: return labelPillWidth(for: label)
        case .nametag: return nametagWidth(for: label)
        }
    }

    static func size(for petAppearance: PetAppearance) -> CGSize {
        let labelWidth = labelWidth(for: petAppearance.label, placement: petAppearance.labelPlacement)
        let bubbleWidth = bubbleWidth(symbol: PetBubbleSymbol.forMood(petAppearance.mood), caption: petAppearance.bubbleCaption)
        return CGSize(
            width: ceil(max(petAppearance.spriteSideLength, labelWidth, bubbleWidth)),
            height: ceil(PetGeometry.totalHeight(
                spriteSideLength: petAppearance.spriteSideLength,
                labelPlacement: petAppearance.labelPlacement
            ))
        )
    }

    func drawChromePart(_ part: PetChromePart) {
        guard chromeOpacity > 0, let graphicsContext = NSGraphicsContext.current else { return }
        graphicsContext.saveGraphicsState()
        graphicsContext.cgContext.setAlpha(min(chromeOpacity, 1))
        switch part {
        case .label:
            switch petAppearance.labelPlacement {
            case .pill: drawLabelPill()
            case .nametag: drawNametag()
            }
        case .bubble:
            let bubbleSymbol = PetBubbleSymbol.forMood(petAppearance.mood)
            if bubbleSymbol != nil || petAppearance.bubbleCaption != nil {
                drawBubble(symbol: bubbleSymbol, caption: petAppearance.bubbleCaption)
            }
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
            x: (contentBounds.width - pillWidth) / 2,
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
            x: ((contentBounds.width - tagWidth) / 2).rounded(),
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
            x: (contentBounds.width - bubbleWidth) / 2,
            y: bubbleBaseline,
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

    static func bubbleWidth(symbol: PetBubbleSymbol?, caption: String?) -> CGFloat {
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

enum PetChromePart {
    case label
    case bubble
}

final class PetChromePartView: NSView {
    let part: PetChromePart
    weak var owner: PetView?

    init(part: PetChromePart) {
        self.part = part
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        owner?.drawChromePart(part)
    }
}

final class PetSpriteView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    var drawsThroughLayerContents = true {
        didSet { needsDisplay = true }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var wantsUpdateLayer: Bool { drawsThroughLayerContents }

    override func updateLayer() {
        guard let layer else { return }
        layer.backgroundColor = PetView.clickTargetColor.cgColor
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        layer.contentsGravity = .resize
        layer.contents = image
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, let graphicsContext = NSGraphicsContext.current else { return }
        graphicsContext.imageInterpolation = .none
        PetView.clickTargetColor.setFill()
        bounds.fill()
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }
}
