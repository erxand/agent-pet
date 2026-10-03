import AgentPetCore
import AppKit

class DemoPanelView: NSView {
    var preferredSize: CGSize { bounds.size }
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

final class DemoCaptionView: DemoPanelView {
    static let hintText = "space: next   esc: quit"

    private static let unit = DemoPanelFrame.unit
    private static let lineGap: CGFloat = 6 * unit
    private static let barHeight: CGFloat = 3 * unit
    private static let barGap: CGFloat = 6 * unit
    private static let hintGap: CGFloat = 8 * unit
    private static let minimumBarWidth: CGFloat = 60 * unit

    let caption: DemoCaption
    private let captionStyle: DemoTextStyle
    private let smallStyle = DemoTextStyle.muted(pixelSide: DemoPanelFrame.smallPixelSide)

    var progress: Double = 0 {
        didSet {
            if abs(progress - oldValue) > 0.001 { needsDisplay = true }
        }
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
            + DemoPixelPainter.size(of: DemoCaptionView.hintText, style: smallStyle).width
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
        let hintWidth = DemoPixelPainter.size(of: DemoCaptionView.hintText, style: smallStyle).width
        let counterWidth = DemoPixelPainter.size(of: counterText, style: smallStyle).width
        let hintLeft = bounds.maxX - padding - hintWidth
        let counterLeft = hintLeft - DemoCaptionView.hintGap - counterWidth
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
        DemoPixelPainter.draw(DemoCaptionView.hintText, topLeft: CGPoint(x: hintLeft, y: textTop), style: smallStyle)
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

final class DemoTitleView: DemoPanelView {
    private static let unit = DemoPanelFrame.unit
    private static let underlineHeight: CGFloat = 2 * unit
    private static let underlineGap: CGFloat = 4 * unit
    private static let subtitleGap: CGFloat = 10 * unit

    let card: DemoTitleCard
    private let titleStyle = DemoTextStyle.text(pixelSide: DemoPanelFrame.titlePixelSide)
    private let subtitleStyle = DemoTextStyle.text(pixelSide: DemoPanelFrame.bodyPixelSide)

    init(card: DemoTitleCard) {
        self.card = card
        super.init(frame: .zero)
        setFrameSize(computedSize())
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var preferredSize: CGSize { computedSize() }

    private func computedSize() -> CGSize {
        let titleSize = DemoPixelPainter.size(of: card.title, style: titleStyle)
        let subtitleSize = DemoPixelPainter.size(of: card.subtitle, style: subtitleStyle)
        let contentWidth = max(titleSize.width, subtitleSize.width)
        let contentHeight = titleSize.height + DemoTitleView.underlineGap + DemoTitleView.underlineHeight
            + DemoTitleView.subtitleGap + subtitleSize.height
        return CGSize(
            width: ceil(contentWidth + DemoPanelFrame.padding * 2),
            height: ceil(contentHeight + DemoPanelFrame.padding * 2)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        DemoPanelFrame.draw(in: bounds, accentStripe: nil)
        let titleSize = DemoPixelPainter.size(of: card.title, style: titleStyle)
        let titleLeft = ((bounds.width - titleSize.width) / 2).rounded()
        let titleTop = bounds.maxY - DemoPanelFrame.padding
        DemoPixelPainter.draw(card.title, topLeft: CGPoint(x: titleLeft, y: titleTop), style: titleStyle)

        let underlineTop = titleTop - titleSize.height - DemoTitleView.underlineGap
        DemoPalette.accentColor(card.accent).setFill()
        CGRect(
            x: titleLeft,
            y: underlineTop - DemoTitleView.underlineHeight,
            width: titleSize.width,
            height: DemoTitleView.underlineHeight
        ).fill()

        let subtitleSize = DemoPixelPainter.size(of: card.subtitle, style: subtitleStyle)
        DemoPixelPainter.draw(
            card.subtitle,
            topLeft: CGPoint(
                x: ((bounds.width - subtitleSize.width) / 2).rounded(),
                y: DemoPanelFrame.padding + subtitleSize.height
            ),
            style: subtitleStyle
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

    init(sideLength: CGFloat) {
        super.init(frame: CGRect(x: 0, y: 0, width: sideLength, height: sideLength))
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let dash = DemoEmptySpotView.dashLength
        let line = DemoEmptySpotView.lineWidth
        DemoPalette.mutedText.withAlphaComponent(0.6).setFill()
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
    private static let lineGap: CGFloat = 4 * unit
    private static let blockCursorGap: CGFloat = 2 * unit
    private static let minimumWidth: CGFloat = 240 * unit
    private static let dotAccents: [AccentColor] = [.red, .yellow, .green]

    let card: DemoTerminalCard
    private let titleStyle = DemoTextStyle.text(pixelSide: DemoPanelFrame.smallPixelSide)
    private let promptStyle = DemoTextStyle.muted(pixelSide: DemoPanelFrame.bodyPixelSide)
    private let lineStyle = DemoTextStyle.text(pixelSide: DemoPanelFrame.bodyPixelSide)

    init(card: DemoTerminalCard) {
        self.card = card
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

    private var lineHeight: CGFloat {
        DemoPixelPainter.size(of: "A", style: lineStyle).height
    }

    private func computedSize() -> CGSize {
        let widest = card.lines.map { line in DemoPixelPainter.size(of: line, style: lineStyle).width }.max() ?? 0
        let contentWidth = max(widest + DemoTerminalView.blockCursorGap + blockCursorWidth, DemoTerminalView.minimumWidth)
        let linesHeight = CGFloat(card.lines.count) * lineHeight + CGFloat(max(0, card.lines.count - 1)) * DemoTerminalView.lineGap
        return CGSize(
            width: ceil(contentWidth + DemoPanelFrame.padding * 2),
            height: ceil(titleBarHeight + DemoTerminalView.underlineHeight + linesHeight + DemoPanelFrame.padding * 2)
        )
    }

    private var blockCursorWidth: CGFloat {
        CGFloat(DemoPixelFont.capHeight) * DemoPanelFrame.bodyPixelSide * 0.7
    }

    override func draw(_ dirtyRect: NSRect) {
        DemoPanelFrame.draw(in: bounds, accentStripe: nil)
        let inner = bounds.insetBy(dx: DemoPanelFrame.unit * 2, dy: DemoPanelFrame.unit * 2)
        let titleBar = CGRect(x: inner.minX, y: inner.maxY - titleBarHeight, width: inner.width, height: titleBarHeight)
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

        var lineTop = titleBar.minY - DemoTerminalView.underlineHeight - DemoPanelFrame.padding
        for (lineIndex, line) in card.lines.enumerated() {
            let isPrompt = line.hasPrefix("~") || line.hasPrefix(">")
            DemoPixelPainter.draw(line, topLeft: CGPoint(x: DemoPanelFrame.padding, y: lineTop), style: isPrompt ? promptStyle : lineStyle)
            if lineIndex == card.lines.count - 1 {
                let lineWidth = DemoPixelPainter.size(of: line, style: lineStyle).width
                let capHeight = CGFloat(DemoPixelFont.capHeight) * DemoPanelFrame.bodyPixelSide
                DemoPalette.text.setFill()
                CGRect(
                    x: DemoPanelFrame.padding + lineWidth + DemoTerminalView.blockCursorGap,
                    y: lineTop - capHeight,
                    width: blockCursorWidth.rounded(),
                    height: capHeight
                ).fill()
            }
            lineTop -= lineHeight + DemoTerminalView.lineGap
        }
    }
}
