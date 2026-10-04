import AgentPetCore
import AppKit

struct DemoTextStyle {
    let color: NSColor
    let pixelSide: CGFloat

    static func text(pixelSide: CGFloat) -> DemoTextStyle {
        DemoTextStyle(color: DemoPalette.text, pixelSide: pixelSide)
    }

    static func muted(pixelSide: CGFloat) -> DemoTextStyle {
        DemoTextStyle(color: DemoPalette.mutedText, pixelSide: pixelSide)
    }
}

enum DemoPixelPainter {
    private static let substituteCharacter: Character = "?"

    static func drawable(_ text: String) -> String {
        String(text.map { character in DemoPixelFont.canRender(String(character)) ? character : substituteCharacter })
    }

    static func size(of text: String, style: DemoTextStyle) -> CGSize {
        CGSize(
            width: CGFloat(DemoPixelFont.width(of: drawable(text))) * style.pixelSide,
            height: CGFloat(DemoPixelFont.glyphHeight) * style.pixelSide
        )
    }

    static func draw(_ text: String, topLeft: CGPoint, style: DemoTextStyle) {
        guard let rows = DemoPixelFont.rows(for: drawable(text)) else { return }
        drawRows(rows, topLeft: topLeft, pixelSide: style.pixelSide, color: style.color)
    }

    static func boldSize(of text: String, style: DemoTextStyle) -> CGSize {
        let size = size(of: text, style: style)
        return CGSize(width: size.width + CGFloat(drawable(text).count) * style.pixelSide, height: size.height)
    }

    static func drawBold(_ text: String, topLeft: CGPoint, style: DemoTextStyle) {
        var left = topLeft.x
        for character in drawable(text) {
            let glyph = String(character)
            draw(glyph, topLeft: CGPoint(x: left, y: topLeft.y), style: style)
            draw(glyph, topLeft: CGPoint(x: left + style.pixelSide, y: topLeft.y), style: style)
            left += CGFloat(DemoPixelFont.width(of: glyph) + DemoPixelFont.glyphSpacing + 1) * style.pixelSide
        }
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
}
