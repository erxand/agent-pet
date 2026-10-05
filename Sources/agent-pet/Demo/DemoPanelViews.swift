import AgentPetCore
import AppKit

class DemoPanelView: NSView {
    var onClick: (() -> Void)?

    var preferredSize: CGSize { bounds.size }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onClick?()
    }
}

protocol DemoKeyHintShowing: AnyObject {
    var hasFocus: Bool { get set }
}

enum DemoPanelFrame {
    static let unit: CGFloat = 2
    static let padding: CGFloat = 9 * unit
    static let bodyPixelSide: CGFloat = 3
    static let smallPixelSide: CGFloat = 2
    static let titlePixelSide: CGFloat = 8
    static let accentStripeWidth: CGFloat = 2 * unit

    static func draw(in bounds: CGRect, accentStripe: NSColor?) {
        NSGraphicsContext.current?.imageInterpolation = .none
        DemoPixelPainter.fillCutCorners(bounds, unit: unit, color: DemoPalette.frame)
        DemoPixelPainter.fillCutCorners(bounds.insetBy(dx: unit, dy: unit), unit: unit, color: DemoPalette.rim)
        let fillRect = bounds.insetBy(dx: unit * 2, dy: unit * 2)
        DemoPalette.fill.setFill()
        fillRect.fill()
        guard let accentStripe else { return }
        accentStripe.setFill()
        CGRect(x: fillRect.minX, y: fillRect.minY, width: accentStripeWidth, height: fillRect.height).fill()
    }
}

final class DemoCaptionView: DemoPanelView, DemoKeyHintShowing {
    private static let hintTexts = [DemoScript.keyHint(hasFocus: true), DemoScript.keyHint(hasFocus: false)]

    private static let unit = DemoPanelFrame.unit
    private static let lineGap: CGFloat = 6 * unit
    private static let barHeight: CGFloat = 3 * unit
    private static let barGap: CGFloat = 6 * unit
    private static let hintGap: CGFloat = 8 * unit
    private static let minimumBarWidth: CGFloat = 60 * unit
    private static let redrawProgressStep = 0.001

    let caption: DemoCaption
    private let captionStyle: DemoTextStyle
    private let smallStyle = DemoTextStyle.muted(pixelSide: DemoPanelFrame.smallPixelSide)
    private let unfocusedHintStyle = DemoTextStyle.text(pixelSide: DemoPanelFrame.smallPixelSide)

    var progress: Double = 0 {
        didSet {
            if abs(progress - oldValue) > DemoCaptionView.redrawProgressStep { needsDisplay = true }
        }
    }

    var hasFocus = true {
        didSet {
            if hasFocus != oldValue { needsDisplay = true }
        }
    }

    private var hintText: String { DemoScript.keyHint(hasFocus: hasFocus) }

    private var widestHintWidth: CGFloat {
        DemoCaptionView.hintTexts.map { text in DemoPixelPainter.size(of: text, style: smallStyle).width }.max() ?? 0
    }

    init(caption: DemoCaption, maximumWidth: CGFloat) {
        self.caption = caption
        let bodyStyle = DemoTextStyle.text(pixelSide: DemoPanelFrame.bodyPixelSide)
        let bodyWidth = DemoPixelPainter.size(of: caption.text, style: bodyStyle).width + DemoPanelFrame.padding * 2
        captionStyle = bodyWidth <= maximumWidth ? bodyStyle : DemoTextStyle.text(pixelSide: DemoPanelFrame.smallPixelSide)
        super.init(frame: .zero)
        setFrameSize(computedSize())
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var preferredSize: CGSize { computedSize() }

    private var accentColor: NSColor { DemoPalette.accentColor(caption.accent) }

    private var counterText: String {
        "\(caption.sceneNumber)/\(caption.sceneCount)"
    }

    private func computedSize() -> CGSize {
        let captionSize = DemoPixelPainter.size(of: caption.text, style: captionStyle)
        let footerTextWidth = DemoPixelPainter.size(of: counterText, style: smallStyle).width
            + DemoCaptionView.hintGap
            + widestHintWidth
        let footerWidth = DemoCaptionView.minimumBarWidth + DemoCaptionView.barGap + footerTextWidth
        let footerHeight = max(DemoCaptionView.barHeight, DemoPixelPainter.size(of: counterText, style: smallStyle).height)
        let contentWidth = max(captionSize.width, footerWidth)
        return CGSize(
            width: ceil(contentWidth + DemoPanelFrame.padding * 2),
            height: ceil(DemoPanelFrame.padding * 2 + captionSize.height + DemoCaptionView.lineGap + footerHeight)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        DemoPanelFrame.draw(in: bounds, accentStripe: accentColor)
        let padding = DemoPanelFrame.padding
        DemoPixelPainter.draw(caption.text, topLeft: CGPoint(x: padding, y: bounds.maxY - padding), style: captionStyle)

        let footerTextHeight = DemoPixelPainter.size(of: counterText, style: smallStyle).height
        let hintWidth = DemoPixelPainter.size(of: hintText, style: smallStyle).width
        let counterWidth = DemoPixelPainter.size(of: counterText, style: smallStyle).width
        let hintLeft = bounds.maxX - padding - hintWidth
        let counterLeft = bounds.maxX - padding - widestHintWidth - DemoCaptionView.hintGap - counterWidth
        let textTop = padding + footerTextHeight
        let capTop = textTop - DemoPanelFrame.smallPixelSide * CGFloat(DemoPixelFont.capHeight)
        let barRect = CGRect(
            x: padding,
            y: ((textTop + capTop) / 2 - DemoCaptionView.barHeight / 2).rounded(),
            width: counterLeft - DemoCaptionView.barGap - padding,
            height: DemoCaptionView.barHeight
        )
        drawProgressBar(in: barRect)
        DemoPixelPainter.draw(counterText, topLeft: CGPoint(x: counterLeft, y: textTop), style: smallStyle)
        DemoPixelPainter.draw(hintText, topLeft: CGPoint(x: hintLeft, y: textTop), style: hasFocus ? smallStyle : unfocusedHintStyle)
    }

    private func drawProgressBar(in rect: CGRect) {
        let unit = DemoCaptionView.unit
        DemoPalette.frame.setFill()
        rect.fill()
        let track = rect.insetBy(dx: unit, dy: unit)
        let filledWidth = (track.width * CGFloat(min(max(progress, 0), 1)) / unit).rounded(.down) * unit
        guard filledWidth > 0 else { return }
        accentColor.setFill()
        CGRect(x: track.minX, y: track.minY, width: filledWidth, height: track.height).fill()
    }
}

final class DemoTitleView: DemoPanelView, DemoKeyHintShowing {
    static let screenWidthFraction: CGFloat = 0.6
    static let widestCard: CGFloat = 1100

    private static let unit = DemoPanelFrame.unit
    private static let horizontalPadding = DemoPanelFrame.padding * 2
    private static let topPadding = DemoPanelFrame.padding * 1.5
    private static let bottomPadding = DemoPanelFrame.padding * 2
    private static let titleLineGap: CGFloat = 4 * unit
    private static let underlineHeight: CGFloat = 2 * unit
    private static let underlineGap: CGFloat = 4 * unit
    private static let subtitleGap: CGFloat = 22 * unit
    private static let subtitleLineGap: CGFloat = 5 * unit
    private static let hintGap: CGFloat = 16 * unit

    static func maximumWidth(screenWidth: CGFloat) -> CGFloat {
        min(screenWidth * screenWidthFraction, widestCard)
    }

    let card: DemoTitleCard
    private let titleStyle = DemoTextStyle.text(pixelSide: DemoPanelFrame.titlePixelSide)
    private let subtitleStyle = DemoTextStyle.text(pixelSide: DemoPanelFrame.bodyPixelSide)
    private let hintStyle = DemoTextStyle.muted(pixelSide: DemoPanelFrame.smallPixelSide)
    private let unfocusedHintStyle = DemoTextStyle.text(pixelSide: DemoPanelFrame.smallPixelSide)
    private let titleLines: [String]
    private let subtitleLines: [String]

    var hasFocus = true {
        didSet {
            if hasFocus != oldValue { needsDisplay = true }
        }
    }

    init(card: DemoTitleCard, maximumWidth: CGFloat) {
        self.card = card
        let textWidth = maximumWidth - DemoTitleView.horizontalPadding * 2
        titleLines = DemoPixelPainter.wrap(card.title, style: titleStyle, maximumWidth: textWidth)
        subtitleLines = DemoPixelPainter.wrap(card.subtitle, style: subtitleStyle, maximumWidth: textWidth)
        super.init(frame: .zero)
        setFrameSize(computedSize())
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var preferredSize: CGSize { computedSize() }

    private func width(of lines: [String], style: DemoTextStyle) -> CGFloat {
        lines.map { line in DemoPixelPainter.size(of: line, style: style).width }.max() ?? 0
    }

    private func height(of lines: [String], style: DemoTextStyle, gap: CGFloat) -> CGFloat {
        let lineHeight = DemoPixelPainter.size(of: "A", style: style).height
        return CGFloat(lines.count) * lineHeight + CGFloat(max(0, lines.count - 1)) * gap
    }

    private var hintSize: CGSize {
        DemoPixelPainter.size(of: DemoScript.keyHint(hasFocus: false), style: hintStyle)
    }

    private func computedSize() -> CGSize {
        let contentWidth = max(width(of: titleLines, style: titleStyle), width(of: subtitleLines, style: subtitleStyle), hintSize.width)
        let contentHeight = height(of: titleLines, style: titleStyle, gap: DemoTitleView.titleLineGap)
            + DemoTitleView.underlineGap + DemoTitleView.underlineHeight
            + DemoTitleView.subtitleGap + height(of: subtitleLines, style: subtitleStyle, gap: DemoTitleView.subtitleLineGap)
            + DemoTitleView.hintGap + hintSize.height
        return CGSize(
            width: ceil(contentWidth + DemoTitleView.horizontalPadding * 2),
            height: ceil(contentHeight + DemoTitleView.topPadding + DemoTitleView.bottomPadding)
        )
    }

    private func drawCentered(_ lines: [String], style: DemoTextStyle, gap: CGFloat, top: CGFloat) -> CGFloat {
        var lineTop = top
        let lineHeight = DemoPixelPainter.size(of: "A", style: style).height
        for line in lines {
            let lineWidth = DemoPixelPainter.size(of: line, style: style).width
            DemoPixelPainter.draw(line, topLeft: CGPoint(x: ((bounds.width - lineWidth) / 2).rounded(), y: lineTop), style: style)
            lineTop -= lineHeight + gap
        }
        return lineTop + gap
    }

    override func draw(_ dirtyRect: NSRect) {
        DemoPanelFrame.draw(in: bounds, accentStripe: nil)
        let titleBottom = drawCentered(titleLines, style: titleStyle, gap: DemoTitleView.titleLineGap, top: bounds.maxY - DemoTitleView.topPadding)

        let underlineWidth = width(of: titleLines, style: titleStyle)
        DemoPalette.accentColor(card.accent).setFill()
        let underlineTop = titleBottom - DemoTitleView.underlineGap
        CGRect(
            x: ((bounds.width - underlineWidth) / 2).rounded(),
            y: underlineTop - DemoTitleView.underlineHeight,
            width: underlineWidth,
            height: DemoTitleView.underlineHeight
        ).fill()

        let subtitleTop = underlineTop - DemoTitleView.underlineHeight - DemoTitleView.subtitleGap
        _ = drawCentered(subtitleLines, style: subtitleStyle, gap: DemoTitleView.subtitleLineGap, top: subtitleTop)

        let hintText = DemoScript.keyHint(hasFocus: hasFocus)
        let shownHintSize = DemoPixelPainter.size(of: hintText, style: hintStyle)
        DemoPixelPainter.draw(
            hintText,
            topLeft: CGPoint(x: ((bounds.width - shownHintSize.width) / 2).rounded(), y: DemoTitleView.bottomPadding + shownHintSize.height),
            style: hasFocus ? hintStyle : unfocusedHintStyle
        )
    }
}

final class DemoStateLabelView: DemoPanelView {
    private static let padding: CGFloat = 6 * DemoPanelFrame.unit
    private static let laneMargin: CGFloat = 12 * DemoPanelFrame.unit

    static func pixelSide(for marks: [DemoStateMark], laneSpacing: CGFloat) -> CGFloat {
        let fits = marks.allSatisfy { mark in
            DemoStateLabelView(mark: mark, pixelSide: DemoPanelFrame.bodyPixelSide).preferredSize.width + laneMargin <= laneSpacing
        }
        return fits ? DemoPanelFrame.bodyPixelSide : DemoPanelFrame.smallPixelSide
    }

    let mark: DemoStateMark
    private let textStyle: DemoTextStyle

    init(mark: DemoStateMark, pixelSide: CGFloat) {
        self.mark = mark
        textStyle = DemoTextStyle.text(pixelSide: pixelSide)
        super.init(frame: .zero)
        setFrameSize(computedSize())
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var preferredSize: CGSize { computedSize() }

    private func computedSize() -> CGSize {
        let textSize = DemoPixelPainter.size(of: mark.label, style: textStyle)
        return CGSize(
            width: ceil(textSize.width + DemoStateLabelView.padding * 2 + DemoPanelFrame.accentStripeWidth),
            height: ceil(textSize.height + DemoStateLabelView.padding * 2)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        DemoPanelFrame.draw(in: bounds, accentStripe: DemoPalette.accentColor(mark.accent))
        let textSize = DemoPixelPainter.size(of: mark.label, style: textStyle)
        DemoPixelPainter.draw(
            mark.label,
            topLeft: CGPoint(
                x: DemoStateLabelView.padding + DemoPanelFrame.accentStripeWidth,
                y: ((bounds.height + textSize.height) / 2).rounded()
            ),
            style: textStyle
        )
    }
}

final class DemoEmptySpotView: DemoPanelView {
    private static let dashLength: CGFloat = 4 * DemoPanelFrame.unit
    private static let lineWidth = DemoPanelFrame.unit
    private static let lineOpacity: CGFloat = 0.6

    init(sideLength: CGFloat) {
        super.init(frame: CGRect(x: 0, y: 0, width: sideLength, height: sideLength))
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let dash = DemoEmptySpotView.dashLength
        let line = DemoEmptySpotView.lineWidth
        DemoPalette.mutedText.withAlphaComponent(DemoEmptySpotView.lineOpacity).setFill()
        var position: CGFloat = 0
        while position < bounds.width {
            let length = min(dash, bounds.width - position)
            CGRect(x: position, y: 0, width: length, height: line).fill()
            CGRect(x: position, y: bounds.height - line, width: length, height: line).fill()
            CGRect(x: 0, y: position, width: line, height: length).fill()
            CGRect(x: bounds.width - line, y: position, width: line, height: length).fill()
            position += dash * 2
        }
    }
}

final class DemoCursorView: DemoPanelView {
    static let pixelSide: CGFloat = 4
    private static let aimHeightFraction: CGFloat = 0.85
    private static let aimRightFraction: CGFloat = 0.35
    private static let outline: Character = "O"
    private static let body: Character = "X"
    private static let rows = [
        "O...........",
        "OO..........",
        "OXO.........",
        "OXXO........",
        "OXXXO.......",
        "OXXXXO......",
        "OXXXXXO.....",
        "OXXXXXXO....",
        "OXXXXXXXO...",
        "OXXXXXXXXO..",
        "OXXXXXOOOOO.",
        "OXXOXXO.....",
        "OXO.OXXO....",
        "OO..OXXO....",
        "O....OXXO...",
        ".....OXXO...",
        "......OO...."
    ]

    static func aim(petCenterX: CGFloat, petBottom: CGFloat, spriteSideLength: CGFloat) -> CGPoint {
        CGPoint(
            x: petCenterX + spriteSideLength * aimRightFraction,
            y: petBottom + PetGeometry.spriteBaseline(labelPlacement: .pill) + spriteSideLength * aimHeightFraction
        )
    }

    init() {
        let width = CGFloat(DemoCursorView.rows.first?.count ?? 0) * DemoCursorView.pixelSide
        let height = CGFloat(DemoCursorView.rows.count) * DemoCursorView.pixelSide
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: height))
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let side = DemoCursorView.pixelSide
        for (rowIndex, row) in DemoCursorView.rows.enumerated() {
            let rowBottom = bounds.maxY - CGFloat(rowIndex + 1) * side
            for (columnIndex, character) in row.enumerated() {
                switch character {
                case DemoCursorView.outline: DemoPalette.frame.setFill()
                case DemoCursorView.body: DemoPalette.text.setFill()
                default: continue
                }
                CGRect(x: CGFloat(columnIndex) * side, y: rowBottom, width: side, height: side).fill()
            }
        }
    }
}

final class DemoTerminalView: DemoPanelView {
    private static let unit = DemoPanelFrame.unit
    private static let titleBarPadding: CGFloat = 5 * unit
    private static let dotSide: CGFloat = 4 * unit
    private static let dotGap: CGFloat = 3 * unit
    private static let underlineHeight: CGFloat = 1 * unit
    private static let mascotGap: CGFloat = 8 * unit
    private static let headerLineGap: CGFloat = 3 * unit
    private static let sectionGap: CGFloat = 9 * unit
    private static let messageGap: CGFloat = 5 * unit
    private static let ruleGap: CGFloat = 4 * unit
    private static let ruleHeight: CGFloat = 1 * unit
    private static let ruleOpacity: CGFloat = 0.45
    private static let blockCursorWidthFraction: CGFloat = 0.7
    private static let wordGap: CGFloat = 6 * unit
    private static let minimumWidth: CGFloat = 240 * unit
    private static let dotAccents: [AccentColor] = [.red, .yellow, .green]

    let card: DemoTerminalCard
    private let mascot: NSImage?
    private let titleStyle = DemoTextStyle.text(pixelSide: DemoPanelFrame.smallPixelSide)
    private let productStyle = DemoTextStyle.text(pixelSide: DemoPanelFrame.bodyPixelSide)
    private let detailStyle = DemoTextStyle.muted(pixelSide: DemoPanelFrame.smallPixelSide)
    private let mutedBodyStyle = DemoTextStyle.muted(pixelSide: DemoPanelFrame.bodyPixelSide)
    private let bodyStyle = DemoTextStyle.text(pixelSide: DemoPanelFrame.bodyPixelSide)
    private var accentBodyStyle: DemoTextStyle {
        DemoTextStyle(color: DemoPalette.accentColor(card.accent), pixelSide: DemoPanelFrame.bodyPixelSide)
    }

    init(card: DemoTerminalCard, mascot: NSImage?) {
        self.card = card
        self.mascot = mascot
        super.init(frame: .zero)
        setFrameSize(computedSize())
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var preferredSize: CGSize { computedSize() }

    private var titleBarHeight: CGFloat {
        DemoPixelPainter.size(of: card.title, style: titleStyle).height + DemoTerminalView.titleBarPadding * 2
    }

    private var bodyLineHeight: CGFloat { DemoPixelPainter.size(of: "A", style: bodyStyle).height }

    private var smallLineHeight: CGFloat { DemoPixelPainter.size(of: "A", style: detailStyle).height }

    private var headerTextHeight: CGFloat {
        bodyLineHeight + DemoTerminalView.headerLineGap + smallLineHeight
    }

    private var mascotSize: CGSize { mascot?.size ?? .zero }

    private var headerHeight: CGFloat { max(headerTextHeight, mascotSize.height) }

    private var headerTextLeft: CGFloat {
        DemoPanelFrame.padding + (mascot == nil ? 0 : mascotSize.width + DemoTerminalView.mascotGap)
    }

    private var blockCursorWidth: CGFloat {
        (CGFloat(DemoPixelFont.capHeight) * DemoPanelFrame.bodyPixelSide * DemoTerminalView.blockCursorWidthFraction).rounded()
    }

    private func prefixedWidth(_ prefix: String, _ text: String) -> CGFloat {
        DemoPixelPainter.size(of: prefix, style: bodyStyle).width + DemoTerminalView.wordGap
            + DemoPixelPainter.size(of: text, style: bodyStyle).width
    }

    private func computedSize() -> CGSize {
        let headerWidth = headerTextLeft - DemoPanelFrame.padding + max(
            DemoPixelPainter.boldSize(of: card.productName, style: productStyle).width,
            DemoPixelPainter.size(of: card.directory, style: detailStyle).width
        )
        let contentWidth = max(
            headerWidth,
            prefixedWidth(DemoTerminalCard.userPrompt, card.userMessage),
            prefixedWidth(DemoTerminalCard.replyBullet, card.reply),
            DemoPixelPainter.size(of: card.statusLine, style: detailStyle).width,
            DemoTerminalView.minimumWidth
        )
        let ruleBlock = DemoTerminalView.ruleGap * 2 + DemoTerminalView.ruleHeight
        let bodyHeight = headerHeight + DemoTerminalView.sectionGap
            + bodyLineHeight + DemoTerminalView.messageGap + bodyLineHeight + DemoTerminalView.sectionGap
            + DemoTerminalView.ruleHeight + DemoTerminalView.ruleGap + bodyLineHeight + ruleBlock + smallLineHeight
        return CGSize(
            width: ceil(contentWidth + DemoPanelFrame.padding * 2),
            height: ceil(titleBarHeight + DemoTerminalView.underlineHeight + bodyHeight + DemoPanelFrame.padding * 2)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        DemoPanelFrame.draw(in: bounds, accentStripe: nil)
        let inner = bounds.insetBy(dx: DemoPanelFrame.unit * 2, dy: DemoPanelFrame.unit * 2)
        let titleBar = CGRect(x: inner.minX, y: inner.maxY - titleBarHeight, width: inner.width, height: titleBarHeight)
        drawTitleBar(titleBar, inner: inner)

        let left = DemoPanelFrame.padding
        let right = bounds.maxX - DemoPanelFrame.padding
        var top = titleBar.minY - DemoTerminalView.underlineHeight - DemoPanelFrame.padding

        if let mascot {
            NSGraphicsContext.current?.imageInterpolation = .none
            let mascotTop = top - ((headerHeight - mascotSize.height) / 2).rounded()
            mascot.draw(in: CGRect(x: left, y: mascotTop - mascotSize.height, width: mascotSize.width, height: mascotSize.height))
        }
        var headerTop = top - ((headerHeight - headerTextHeight) / 2).rounded()
        DemoPixelPainter.drawBold(card.productName, topLeft: CGPoint(x: headerTextLeft, y: headerTop), style: productStyle)
        headerTop -= bodyLineHeight + DemoTerminalView.headerLineGap
        DemoPixelPainter.draw(card.directory, topLeft: CGPoint(x: headerTextLeft, y: headerTop), style: detailStyle)
        top -= headerHeight + DemoTerminalView.sectionGap

        drawPrefixed(DemoTerminalCard.userPrompt, prefixStyle: mutedBodyStyle, text: card.userMessage, textStyle: mutedBodyStyle, left: left, top: top)
        top -= bodyLineHeight + DemoTerminalView.messageGap
        drawPrefixed(DemoTerminalCard.replyBullet, prefixStyle: accentBodyStyle, text: card.reply, textStyle: bodyStyle, left: left, top: top)
        top -= bodyLineHeight + DemoTerminalView.sectionGap

        drawRule(left: left, right: right, top: top)
        top -= DemoTerminalView.ruleHeight + DemoTerminalView.ruleGap
        DemoPixelPainter.draw(DemoTerminalCard.inputChevron, topLeft: CGPoint(x: left, y: top), style: mutedBodyStyle)
        let capHeight = CGFloat(DemoPixelFont.capHeight) * DemoPanelFrame.bodyPixelSide
        DemoPalette.text.setFill()
        CGRect(
            x: left + DemoPixelPainter.size(of: DemoTerminalCard.inputChevron, style: bodyStyle).width + DemoTerminalView.wordGap,
            y: top - capHeight,
            width: blockCursorWidth,
            height: capHeight
        ).fill()
        top -= bodyLineHeight + DemoTerminalView.ruleGap
        drawRule(left: left, right: right, top: top)
        top -= DemoTerminalView.ruleHeight + DemoTerminalView.ruleGap
        DemoPixelPainter.draw(card.statusLine, topLeft: CGPoint(x: left, y: top), style: detailStyle)
    }

    private func drawTitleBar(_ titleBar: CGRect, inner: CGRect) {
        DemoPalette.rim.setFill()
        titleBar.fill()
        DemoPalette.accentColor(card.accent).setFill()
        CGRect(x: inner.minX, y: titleBar.minY - DemoTerminalView.underlineHeight, width: inner.width, height: DemoTerminalView.underlineHeight).fill()
        var dotLeft = titleBar.minX + DemoTerminalView.titleBarPadding
        for accent in DemoTerminalView.dotAccents {
            DemoPalette.accentColor(accent).setFill()
            CGRect(x: dotLeft, y: (titleBar.midY - DemoTerminalView.dotSide / 2).rounded(), width: DemoTerminalView.dotSide, height: DemoTerminalView.dotSide).fill()
            dotLeft += DemoTerminalView.dotSide + DemoTerminalView.dotGap
        }
        let titleSize = DemoPixelPainter.size(of: card.title, style: titleStyle)
        DemoPixelPainter.draw(
            card.title,
            topLeft: CGPoint(x: ((bounds.width - titleSize.width) / 2).rounded(), y: (titleBar.midY + titleSize.height / 2).rounded()),
            style: titleStyle
        )
    }

    private func drawPrefixed(_ prefix: String, prefixStyle: DemoTextStyle, text: String, textStyle: DemoTextStyle, left: CGFloat, top: CGFloat) {
        DemoPixelPainter.draw(prefix, topLeft: CGPoint(x: left, y: top), style: prefixStyle)
        let textLeft = left + DemoPixelPainter.size(of: prefix, style: prefixStyle).width + DemoTerminalView.wordGap
        DemoPixelPainter.draw(text, topLeft: CGPoint(x: textLeft, y: top), style: textStyle)
    }

    private func drawRule(left: CGFloat, right: CGFloat, top: CGFloat) {
        DemoPalette.mutedText.withAlphaComponent(DemoTerminalView.ruleOpacity).setFill()
        CGRect(x: left, y: top - DemoTerminalView.ruleHeight, width: right - left, height: DemoTerminalView.ruleHeight).fill()
    }
}
