import AppKit

package enum DemoPalette {
    package static let frameHex: UInt32 = 0x0B0E13
    package static let rimHex: UInt32 = 0x1C222C
    package static let fillHex: UInt32 = 0x252D39
    package static let textHex: UInt32 = 0xECEFF4
    package static let mutedTextHex: UInt32 = 0xA3ADBB
    package static let backdropHex: UInt32 = 0x3B4A5C

    package static let frame = NSColor(hex: frameHex)
    package static let rim = NSColor(hex: rimHex)
    package static let fill = NSColor(hex: fillHex)
    package static let text = NSColor(hex: textHex)
    package static let mutedText = NSColor(hex: mutedTextHex)
    package static let backdrop = NSColor(hex: backdropHex)

    package static let textColors = [text, mutedText]
    package static let textBackgrounds = [fill, rim]

    package static func accentColor(_ accent: AccentColor?) -> NSColor {
        accent?.color ?? mutedText
    }

    package static func contrastRatio(_ first: NSColor, _ second: NSColor) -> Double {
        let lighter = max(relativeLuminance(first), relativeLuminance(second))
        let darker = min(relativeLuminance(first), relativeLuminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    package static func relativeLuminance(_ color: NSColor) -> Double {
        let srgbColor = color.usingColorSpace(.sRGB) ?? color
        func linear(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.039_28 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(srgbColor.redComponent)
            + 0.7152 * linear(srgbColor.greenComponent)
            + 0.0722 * linear(srgbColor.blueComponent)
    }
}
