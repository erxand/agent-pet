import AgentPetCore
import AppKit

enum DemoPalette {
    static let textWhite = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    static let textShadow = NSColor(srgbRed: 0.25, green: 0.25, blue: 0.25, alpha: 1)
    static let textGray = NSColor(srgbRed: 0.67, green: 0.67, blue: 0.67, alpha: 1)
    static let textGrayShadow = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.16, alpha: 1)
    static let textYellow = NSColor(srgbRed: 1, green: 1, blue: 0.33, alpha: 1)
    static let textYellowShadow = NSColor(srgbRed: 0.25, green: 0.25, blue: 0.08, alpha: 1)

    static let tooltipFill = NSColor(srgbRed: 0.06, green: 0, blue: 0.06, alpha: 0.94)
    static let tooltipBorderTop = NSColor(srgbRed: 0.31, green: 0.16, blue: 0.75, alpha: 1)
    static let tooltipBorderBottom = NSColor(srgbRed: 0.16, green: 0.07, blue: 0.40, alpha: 1)

    static let toastFill = NSColor(srgbRed: 0.13, green: 0.13, blue: 0.13, alpha: 0.96)
    static let toastOutline = NSColor(srgbRed: 0.02, green: 0.02, blue: 0.02, alpha: 1)
    static let toastHighlight = NSColor(srgbRed: 0.42, green: 0.42, blue: 0.42, alpha: 1)
    static let toastShade = NSColor(srgbRed: 0.24, green: 0.24, blue: 0.24, alpha: 1)

    static let slotFill = NSColor(srgbRed: 0.55, green: 0.55, blue: 0.55, alpha: 1)
    static let slotDarkEdge = NSColor(srgbRed: 0.22, green: 0.22, blue: 0.22, alpha: 1)
    static let slotLightEdge = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    static let experienceTrack = NSColor(srgbRed: 0.10, green: 0.17, blue: 0.06, alpha: 1)
    static let experienceFill = NSColor(srgbRed: 0.50, green: 1, blue: 0.13, alpha: 1)
    static let experienceFillShade = NSColor(srgbRed: 0.29, green: 0.66, blue: 0.05, alpha: 1)
    static let experienceOutline = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

    static let stoneFace = NSColor(srgbRed: 0.60, green: 0.60, blue: 0.60, alpha: 1)
    static let stoneHighlight = NSColor(srgbRed: 0.80, green: 0.80, blue: 0.80, alpha: 1)
    static let stoneShade = NSColor(srgbRed: 0.40, green: 0.40, blue: 0.40, alpha: 1)
    static let stoneExtrusion = NSColor(srgbRed: 0.17, green: 0.17, blue: 0.17, alpha: 1)

    static let dirtTones: [NSColor] = [
        NSColor(srgbRed: 0.53, green: 0.38, blue: 0.26, alpha: 1),
        NSColor(srgbRed: 0.47, green: 0.33, blue: 0.23, alpha: 1),
        NSColor(srgbRed: 0.35, green: 0.24, blue: 0.16, alpha: 1),
        NSColor(srgbRed: 0.61, green: 0.46, blue: 0.33, alpha: 1),
        NSColor(srgbRed: 0.42, green: 0.29, blue: 0.20, alpha: 1)
    ]
    static let dirtDarkening = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.72)
    static let panelOutline = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
}

struct DemoTextStyle {
    let color: NSColor
    let shadowColor: NSColor?
    let pixelSide: CGFloat

    static func white(pixelSide: CGFloat) -> DemoTextStyle {
        DemoTextStyle(color: DemoPalette.textWhite, shadowColor: DemoPalette.textShadow, pixelSide: pixelSide)
    }

    static func gray(pixelSide: CGFloat) -> DemoTextStyle {
        DemoTextStyle(color: DemoPalette.textGray, shadowColor: DemoPalette.textGrayShadow, pixelSide: pixelSide)
    }

    static func yellow(pixelSide: CGFloat) -> DemoTextStyle {
        DemoTextStyle(color: DemoPalette.textYellow, shadowColor: DemoPalette.textYellowShadow, pixelSide: pixelSide)
    }
}

enum DemoPixelPainter {
    private static let substituteCharacter: Character = "?"

    static func drawable(_ text: String) -> String {
        String(text.map { character in DemoPixelFont.canRender(String(character)) ? character : substituteCharacter })
    }

    static func size(of text: String, style: DemoTextStyle) -> CGSize {
        let shadowExtent = style.shadowColor == nil ? 0 : style.pixelSide
        return CGSize(
            width: CGFloat(DemoPixelFont.width(of: drawable(text))) * style.pixelSide + shadowExtent,
            height: CGFloat(DemoPixelFont.glyphHeight) * style.pixelSide + shadowExtent
        )
    }

    static func draw(_ text: String, topLeft: CGPoint, style: DemoTextStyle) {
        guard let rows = DemoPixelFont.rows(for: drawable(text)) else { return }
        if let shadowColor = style.shadowColor {
            drawRows(
                rows,
                topLeft: CGPoint(x: topLeft.x + style.pixelSide, y: topLeft.y - style.pixelSide),
                pixelSide: style.pixelSide,
                color: shadowColor
            )
        }
        drawRows(rows, topLeft: topLeft, pixelSide: style.pixelSide, color: style.color)
    }

    private static func drawRows(_ rows: [String], topLeft: CGPoint, pixelSide: CGFloat, color: NSColor) {
        color.setFill()
        for (rowIndex, row) in rows.enumerated() {
            let rowTop = topLeft.y - CGFloat(rowIndex + 1) * pixelSide
            for (columnIndex, character) in row.enumerated() where DemoPixelFont.isInk(character) {
                CGRect(x: topLeft.x + CGFloat(columnIndex) * pixelSide, y: rowTop, width: pixelSide, height: pixelSide).fill()
            }
        }
    }

    static func fillCutCorners(_ rect: CGRect, unit: CGFloat, color: NSColor) {
        color.setFill()
        CGRect(x: rect.minX + unit, y: rect.minY, width: rect.width - unit * 2, height: rect.height).fill()
        CGRect(x: rect.minX, y: rect.minY + unit, width: rect.width, height: rect.height - unit * 2).fill()
    }

    static func strokeBevel(_ rect: CGRect, unit: CGFloat, light: NSColor, dark: NSColor) {
        light.setFill()
        CGRect(x: rect.minX, y: rect.maxY - unit, width: rect.width - unit, height: unit).fill()
        CGRect(x: rect.minX, y: rect.minY + unit, width: unit, height: rect.height - unit).fill()
        dark.setFill()
        CGRect(x: rect.minX + unit, y: rect.minY, width: rect.width - unit, height: unit).fill()
        CGRect(x: rect.maxX - unit, y: rect.minY, width: unit, height: rect.height - unit).fill()
    }

    static func stableNoise(column: Int, row: Int, seed: Int) -> Int {
        var value = UInt32(truncatingIfNeeded: column &* 73_856_093 ^ row &* 19_349_663 ^ seed &* 83_492_791)
        value ^= value >> 13
        value = value &* 1_274_126_177
        value ^= value >> 16
        return Int(value & 0xFFFF)
    }
}
