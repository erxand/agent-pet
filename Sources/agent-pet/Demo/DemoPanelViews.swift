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

final class DemoCaptionView: DemoPanelView {
    static let hintText = "click: next   ctrl-c: quit"

    private static let unit: CGFloat = 2
    private static let largeTextPixelSide: CGFloat = 3
    private static let smallTextPixelSide: CGFloat = 2
    private static let horizontalPadding: CGFloat = 7 * unit
    private static let verticalPadding: CGFloat = 6 * unit
    private static let lineGap: CGFloat = 5 * unit
    private static let barHeight: CGFloat = 5 * unit
    private static let barGap: CGFloat = 6 * unit
    private static let hintGap: CGFloat = 8 * unit
    private static let minimumBarWidth: CGFloat = 60 * unit

    let caption: DemoCaption
    private let captionStyle: DemoTextStyle
    private let smallStyle = DemoTextStyle.gray(pixelSide: DemoCaptionView.smallTextPixelSide)

    var progress: Double = 0 {
        didSet {
            if abs(progress - oldValue) > 0.001 { needsDisplay = true }
        }
    }

    init(caption: DemoCaption, maximumWidth: CGFloat) {
        self.caption = caption
        let largeStyle = DemoTextStyle.white(pixelSide: DemoCaptionView.largeTextPixelSide)
        let largeWidth = DemoPixelPainter.size(of: caption.text, style: largeStyle).width
            + DemoCaptionView.horizontalPadding * 2
        captionStyle = largeWidth <= maximumWidth
            ? largeStyle
            : DemoTextStyle.white(pixelSide: DemoCaptionView.smallTextPixelSide)
        super.init(frame: .zero)
        setFrameSize(computedSize())
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var preferredSize: CGSize { computedSize() }

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
            width: ceil(contentWidth + DemoCaptionView.horizontalPadding * 2),
            height: ceil(DemoCaptionView.verticalPadding * 2 + captionSize.height + DemoCaptionView.lineGap + footerHeight)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        let unit = DemoCaptionView.unit
        DemoPixelPainter.fillCutCorners(bounds, unit: unit, color: DemoPalette.tooltipFill)
        drawGradientBorder(in: bounds.insetBy(dx: unit, dy: unit), unit: unit)

        let textLeft = DemoCaptionView.horizontalPadding
        DemoPixelPainter.draw(
            caption.text,
            topLeft: CGPoint(x: textLeft, y: bounds.maxY - DemoCaptionView.verticalPadding),
            style: captionStyle
        )

        let footerTextHeight = DemoPixelPainter.size(of: counterText, style: smallStyle).height
        let footerBottom = DemoCaptionView.verticalPadding
        let hintWidth = DemoPixelPainter.size(of: DemoCaptionView.hintText, style: smallStyle).width
        let counterWidth = DemoPixelPainter.size(of: counterText, style: smallStyle).width
        let hintLeft = bounds.maxX - DemoCaptionView.horizontalPadding - hintWidth
        let counterLeft = hintLeft - DemoCaptionView.hintGap - counterWidth
        let barWidth = counterLeft - DemoCaptionView.barGap - textLeft
        let textTop = footerBottom + footerTextHeight
        let barRect = CGRect(
            x: textLeft,
            y: footerBottom + (footerTextHeight - DemoCaptionView.barHeight) / 2 + unit,
            width: barWidth,
            height: DemoCaptionView.barHeight
        )
        drawExperienceBar(in: barRect, unit: unit)
        DemoPixelPainter.draw(counterText, topLeft: CGPoint(x: counterLeft, y: textTop), style: smallStyle)
        DemoPixelPainter.draw(DemoCaptionView.hintText, topLeft: CGPoint(x: hintLeft, y: textTop), style: smallStyle)
    }

    private func drawGradientBorder(in rect: CGRect, unit: CGFloat) {
        let gradient = NSGradient(starting: DemoPalette.tooltipBorderBottom, ending: DemoPalette.tooltipBorderTop)
        DemoPalette.tooltipBorderTop.setFill()
        CGRect(x: rect.minX, y: rect.maxY - unit, width: rect.width, height: unit).fill()
        DemoPalette.tooltipBorderBottom.setFill()
        CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: unit).fill()
        gradient?.draw(in: CGRect(x: rect.minX, y: rect.minY, width: unit, height: rect.height), angle: 90)
        gradient?.draw(in: CGRect(x: rect.maxX - unit, y: rect.minY, width: unit, height: rect.height), angle: 90)
    }

    private func drawExperienceBar(in rect: CGRect, unit: CGFloat) {
        DemoPalette.experienceOutline.setFill()
        rect.fill()
        let track = rect.insetBy(dx: unit, dy: unit)
        DemoPalette.experienceTrack.setFill()
        track.fill()
        let filledWidth = (track.width * CGFloat(min(max(progress, 0), 1)) / unit).rounded(.down) * unit
        guard filledWidth > 0 else { return }
        DemoPalette.experienceFillShade.setFill()
        CGRect(x: track.minX, y: track.minY, width: filledWidth, height: track.height).fill()
        DemoPalette.experienceFill.setFill()
        CGRect(x: track.minX, y: track.minY + unit, width: filledWidth, height: track.height - unit).fill()
    }
}

final class DemoTitleView: DemoPanelView {
    private static let blockSide: CGFloat = 10
    private static let texelSide: CGFloat = 4
    private static let padding: CGFloat = 32
    private static let extrusionStep: CGFloat = 2
    private static let extrusionSteps = 5
    private static let subtitleGap: CGFloat = 64
    private static let outlineWidth: CGFloat = 2
    private static let splashAngleInDegrees: CGFloat = -12
    private static let splashOverhang: CGFloat = 24
    private static let logoLetterGap = 2
    private static let logoBoldExtraColumns = 1
    private static let dirtSeed = 7
    private static let stoneSeed = 11
    private static let stoneVariationSteps = 5
    private static let stoneVariationAmount: CGFloat = 0.035

    let card: DemoTitleCard
    private let subtitleStyle = DemoTextStyle.white(pixelSide: 3)
    private let splashStyle = DemoTextStyle.yellow(pixelSide: 3)

    init(card: DemoTitleCard) {
        self.card = card
        super.init(frame: .zero)
        setFrameSize(computedSize())
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var preferredSize: CGSize { computedSize() }

    private var logoText: String { card.title.uppercased() }

    private var extrusionDepth: CGFloat {
        DemoTitleView.extrusionStep * CGFloat(DemoTitleView.extrusionSteps)
    }

    private var logoSize: CGSize {
        CGSize(
            width: CGFloat(logoLayout().columnCount) * DemoTitleView.blockSide,
            height: CGFloat(DemoPixelFont.capHeight) * DemoTitleView.blockSide
        )
    }

    private func computedSize() -> CGSize {
        let subtitleSize = DemoPixelPainter.size(of: card.subtitle, style: subtitleStyle)
        let contentWidth = max(logoSize.width + extrusionDepth, subtitleSize.width)
        let height = DemoTitleView.padding * 2
            + logoSize.height + extrusionDepth
            + DemoTitleView.subtitleGap
            + subtitleSize.height
        return CGSize(width: ceil(contentWidth + DemoTitleView.padding * 2), height: ceil(height))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        NSBezierPath(rect: bounds).setClip()
        drawDirtBackground()
        let logoOrigin = CGPoint(
            x: ((bounds.width - logoSize.width - extrusionDepth) / 2).rounded(),
            y: bounds.maxY - DemoTitleView.padding - logoSize.height
        )
        drawLogo(origin: logoOrigin)
        let subtitleSize = DemoPixelPainter.size(of: card.subtitle, style: subtitleStyle)
        DemoPixelPainter.draw(
            card.subtitle,
            topLeft: CGPoint(
                x: ((bounds.width - subtitleSize.width) / 2).rounded(),
                y: DemoTitleView.padding + subtitleSize.height
            ),
            style: subtitleStyle
        )
        if let splash = card.splash {
            drawSplash(splash, near: CGPoint(x: logoOrigin.x + logoSize.width, y: logoOrigin.y - extrusionDepth))
        }
    }

    private func drawDirtBackground() {
        let texel = DemoTitleView.texelSide
        let columns = Int(ceil(bounds.width / texel))
        let rows = Int(ceil(bounds.height / texel))
        for row in 0..<rows {
            for column in 0..<columns {
                let noise = DemoPixelPainter.stableNoise(column: column, row: row, seed: DemoTitleView.dirtSeed)
                DemoPalette.dirtTones[noise % DemoPalette.dirtTones.count].setFill()
                CGRect(x: CGFloat(column) * texel, y: CGFloat(row) * texel, width: texel, height: texel).fill()
            }
        }
        DemoPalette.dirtDarkening.setFill()
        bounds.fill(using: .sourceOver)
        DemoPalette.panelOutline.setStroke()
        let outline = NSBezierPath(rect: bounds.insetBy(dx: DemoTitleView.outlineWidth / 2, dy: DemoTitleView.outlineWidth / 2))
        outline.lineWidth = DemoTitleView.outlineWidth
        outline.stroke()
    }

    private func logoLayout() -> (cells: [(column: Int, row: Int)], columnCount: Int) {
        var cells: [(column: Int, row: Int)] = []
        var cursor = 0
        for character in DemoPixelPainter.drawable(logoText) {
            guard let glyph = DemoPixelFont.glyphRows(for: character) else { continue }
            let glyphWidth = glyph.first?.count ?? 0
            if cursor > 0 { cursor += DemoTitleView.logoLetterGap }
            for (rowIndex, row) in glyph.prefix(DemoPixelFont.capHeight).enumerated() {
                let inks = row.map { character in DemoPixelFont.isInk(character) }
                for column in 0...glyphWidth {
                    let inkHere = column < glyphWidth && inks[column]
                    let inkLeft = column > 0 && inks[column - 1]
                    if inkHere || inkLeft {
                        cells.append((column: cursor + column, row: rowIndex))
                    }
                }
            }
            cursor += glyphWidth + DemoTitleView.logoBoldExtraColumns
        }
        return (cells, cursor)
    }

    private func drawLogo(origin: CGPoint) {
        let side = DemoTitleView.blockSide
        let cells = logoLayout().cells
        func cellRect(_ cell: (column: Int, row: Int), offset: CGFloat) -> CGRect {
            CGRect(
                x: origin.x + CGFloat(cell.column) * side + offset,
                y: origin.y + CGFloat(DemoPixelFont.capHeight - 1 - cell.row) * side - offset,
                width: side,
                height: side
            )
        }
        DemoPalette.stoneExtrusion.setFill()
        for step in stride(from: DemoTitleView.extrusionSteps, through: 1, by: -1) {
            for cell in cells {
                cellRect(cell, offset: CGFloat(step) * DemoTitleView.extrusionStep).fill()
            }
        }
        let bevel = side / 6
        let occupied = Set(cells.map { cell in DemoLogoCell(column: cell.column, row: cell.row) })
        for cell in cells {
            let rect = cellRect(cell, offset: 0)
            let noise = DemoPixelPainter.stableNoise(column: cell.column, row: cell.row, seed: DemoTitleView.stoneSeed)
            let variation = CGFloat(noise % DemoTitleView.stoneVariationSteps - DemoTitleView.stoneVariationSteps / 2)
                * DemoTitleView.stoneVariationAmount
            DemoTitleView.adjusted(DemoPalette.stoneFace, by: variation).setFill()
            rect.fill()
            DemoPalette.stoneHighlight.setFill()
            if !occupied.contains(DemoLogoCell(column: cell.column, row: cell.row - 1)) {
                CGRect(x: rect.minX, y: rect.maxY - bevel, width: rect.width, height: bevel).fill()
            }
            if !occupied.contains(DemoLogoCell(column: cell.column - 1, row: cell.row)) {
                CGRect(x: rect.minX, y: rect.minY, width: bevel, height: rect.height).fill()
            }
            DemoPalette.stoneShade.setFill()
            if !occupied.contains(DemoLogoCell(column: cell.column, row: cell.row + 1)) {
                CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: bevel).fill()
            }
            if !occupied.contains(DemoLogoCell(column: cell.column + 1, row: cell.row)) {
                CGRect(x: rect.maxX - bevel, y: rect.minY, width: bevel, height: rect.height).fill()
            }
        }
    }

    private func drawSplash(_ splash: String, near anchor: CGPoint) {
        guard let graphicsContext = NSGraphicsContext.current else { return }
        let splashSize = DemoPixelPainter.size(of: splash, style: splashStyle)
        let center = CGPoint(
            x: min(anchor.x - splashSize.width / 2 + DemoTitleView.splashOverhang, bounds.maxX - splashSize.width / 2 - DemoTitleView.splashOverhang),
            y: anchor.y - DemoTitleView.subtitleGap / 3
        )
        graphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byDegrees: DemoTitleView.splashAngleInDegrees)
        transform.concat()
        DemoPixelPainter.draw(
            splash,
            topLeft: CGPoint(x: -splashSize.width / 2, y: splashSize.height / 2),
            style: splashStyle
        )
        graphicsContext.restoreGraphicsState()
    }

    private static func adjusted(_ color: NSColor, by amount: CGFloat) -> NSColor {
        let srgbColor = color.usingColorSpace(.sRGB) ?? color
        return NSColor(
            srgbRed: min(max(srgbColor.redComponent + amount, 0), 1),
            green: min(max(srgbColor.greenComponent + amount, 0), 1),
            blue: min(max(srgbColor.blueComponent + amount, 0), 1),
            alpha: srgbColor.alphaComponent
        )
    }
}

private struct DemoLogoCell: Hashable {
    let column: Int
    let row: Int
}

final class DemoToastView: DemoPanelView {
    private static let unit: CGFloat = 2
    private static let height: CGFloat = 32 * unit
    private static let minimumWidth: CGFloat = 160 * unit
    private static let slotSide: CGFloat = 20 * unit
    private static let slotInset: CGFloat = 6 * unit
    private static let textLeft: CGFloat = 32 * unit
    private static let rightPadding: CGFloat = 8 * unit
    private static let titleTop: CGFloat = 27 * unit
    private static let bodyTop: CGFloat = 14 * unit

    let toast: DemoToast
    private let icon: NSImage?
    private let titleStyle = DemoTextStyle.yellow(pixelSide: DemoToastView.unit)
    private let bodyStyle = DemoTextStyle.white(pixelSide: DemoToastView.unit)

    init(toast: DemoToast, icon: NSImage?) {
        self.toast = toast
        self.icon = icon
        super.init(frame: .zero)
        setFrameSize(computedSize())
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var preferredSize: CGSize { computedSize() }

    private func computedSize() -> CGSize {
        let textWidth = max(
            DemoPixelPainter.size(of: toast.title, style: titleStyle).width,
            DemoPixelPainter.size(of: toast.body, style: bodyStyle).width
        )
        return CGSize(
            width: ceil(max(DemoToastView.minimumWidth, DemoToastView.textLeft + textWidth + DemoToastView.rightPadding)),
            height: DemoToastView.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        let unit = DemoToastView.unit
        DemoPixelPainter.fillCutCorners(bounds, unit: unit, color: DemoPalette.toastOutline)
        let inner = bounds.insetBy(dx: unit, dy: unit)
        DemoPalette.toastFill.setFill()
        inner.fill()
        DemoPixelPainter.strokeBevel(inner, unit: unit, light: DemoPalette.toastHighlight, dark: DemoPalette.toastShade)

        let slotRect = CGRect(
            x: DemoToastView.slotInset,
            y: (bounds.height - DemoToastView.slotSide) / 2,
            width: DemoToastView.slotSide,
            height: DemoToastView.slotSide
        )
        DemoPalette.slotFill.setFill()
        slotRect.fill()
        DemoPixelPainter.strokeBevel(slotRect, unit: unit, light: DemoPalette.slotDarkEdge, dark: DemoPalette.slotLightEdge)
        if let icon {
            icon.draw(in: slotRect.insetBy(dx: unit * 2, dy: unit * 2), from: .zero, operation: .sourceOver, fraction: 1)
        }

        DemoPixelPainter.draw(toast.title, topLeft: CGPoint(x: DemoToastView.textLeft, y: DemoToastView.titleTop), style: titleStyle)
        DemoPixelPainter.draw(toast.body, topLeft: CGPoint(x: DemoToastView.textLeft, y: DemoToastView.bodyTop), style: bodyStyle)
    }
}
