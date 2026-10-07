import AppKit

package struct AccentInks: Equatable {
    package let accent: Character
    package let shade: Character?

    package init(accent: Character, shade: Character? = nil) {
        self.accent = accent
        self.shade = shade
    }
}

package enum SpriteAccentTint {
    package static let shadeBrightness: CGFloat = 0.68

    package static func tint(chosenAccent: AccentColor?, accentInks: AccentInks?) -> AccentColor? {
        guard accentInks != nil else { return nil }
        return chosenAccent
    }

    package static func shade(of color: NSColor) -> NSColor {
        let converted = color.usingColorSpace(.sRGB) ?? color
        return NSColor(
            srgbRed: converted.redComponent * shadeBrightness,
            green: converted.greenComponent * shadeBrightness,
            blue: converted.blueComponent * shadeBrightness,
            alpha: converted.alphaComponent
        )
    }

    package static func colorsByCharacter(
        _ colorsByCharacter: [Character: NSColor],
        inks: AccentInks,
        accent: AccentColor
    ) -> [Character: NSColor] {
        var recolored = colorsByCharacter
        if recolored[inks.accent] != nil {
            recolored[inks.accent] = accent.color
        }
        if let shadeCharacter = inks.shade, recolored[shadeCharacter] != nil {
            recolored[shadeCharacter] = shade(of: accent.color)
        }
        return recolored
    }

    package static func tinted(_ sheet: SpriteSheet, inks: AccentInks, accent: AccentColor) -> SpriteSheet {
        SpriteSheet(
            idle: sheet.idle,
            walk: sheet.walk,
            wave: sheet.wave,
            sit: sheet.sit,
            emerge: sheet.emerge,
            dive: sheet.dive,
            jump: sheet.jump,
            fall: sheet.fall,
            colorsByCharacter: colorsByCharacter(sheet.colorsByCharacter, inks: inks, accent: accent)
        )
    }
}
