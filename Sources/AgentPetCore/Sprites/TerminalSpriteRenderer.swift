import AppKit

package enum TerminalSpriteRenderer {
    private static let upperHalfBlock = "\u{2580}"
    private static let lowerHalfBlock = "\u{2584}"
    private static let blank = " "
    private static let escape = "\u{1B}["
    private static let reset = "\u{1B}[0m"
    private static let foregroundTrueColor = "38;2;"
    private static let backgroundTrueColor = "48;2;"
    private static let parameterSeparator = ";"
    private static let sgrTerminator = "m"
    private static let lineSeparator = "\n"
    private static let maximumComponentValue: CGFloat = 255

    package struct TerminalColor: Equatable {
        let red: Int
        let green: Int
        let blue: Int
    }

    package static func render(frame: PixelFrame, palette: SpritePalette) -> String {
        var lines: [String] = []
        var topRow = 0
        while topRow < frame.sideLength {
            let bottomRow = topRow + 1
            var line = ""
            for column in 0..<frame.sideLength {
                let top = color(palette.color(for: frame.character(column: column, row: topRow)))
                let bottom = bottomRow < frame.sideLength
                    ? color(palette.color(for: frame.character(column: column, row: bottomRow)))
                    : nil
                line += cell(top: top, bottom: bottom)
            }
            lines.append(line + reset)
            topRow += 2
        }
        return lines.joined(separator: lineSeparator) + lineSeparator
    }

    private static func cell(top: TerminalColor?, bottom: TerminalColor?) -> String {
        switch (top, bottom) {
        case (nil, nil):
            return reset + blank
        case (let top?, nil):
            return reset + foreground(top) + upperHalfBlock
        case (nil, let bottom?):
            return reset + foreground(bottom) + lowerHalfBlock
        case (let top?, let bottom?):
            return foreground(top) + background(bottom) + upperHalfBlock
        }
    }

    private static func foreground(_ color: TerminalColor) -> String {
        escape + foregroundTrueColor + components(of: color) + sgrTerminator
    }

    private static func background(_ color: TerminalColor) -> String {
        escape + backgroundTrueColor + components(of: color) + sgrTerminator
    }

    private static func components(of color: TerminalColor) -> String {
        [color.red, color.green, color.blue].map { component in String(component) }.joined(separator: parameterSeparator)
    }

    package static func color(_ inkColor: NSColor?) -> TerminalColor? {
        guard let inkColor, let converted = inkColor.usingColorSpace(.sRGB), converted.alphaComponent > 0 else { return nil }
        return TerminalColor(
            red: component(converted.redComponent),
            green: component(converted.greenComponent),
            blue: component(converted.blueComponent)
        )
    }

    private static func component(_ value: CGFloat) -> Int {
        Int((min(max(value, 0), 1) * maximumComponentValue).rounded())
    }
}
