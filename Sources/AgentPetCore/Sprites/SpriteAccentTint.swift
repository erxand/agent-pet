import AppKit

/// The two palette characters a pack hands over to the session accent, from `accentInks` in
/// `pack.json`. `accent` is painted in the accent color and `shade`, when present, in a darker shade.
package struct AccentInks: Equatable {
    package let accent: Character
    package let shade: Character?

    package init(accent: Character, shade: Character? = nil) {
        self.accent = accent
        self.shade = shade
    }
}

/// Paints a pack's accent inks in a session's accent color. Pure: the registry caches the result per
/// pack and accent, so the overlay never recolors on a tick.
package enum SpriteAccentTint {
    /// The shade keeps the accent's hue and saturation at this fraction of its brightness, close to
    /// the shades the shipped packs drew by hand (about 0.7 of the base).
    package static let shadeBrightness: CGFloat = 0.68

    /// The accent a pet's sprite is painted in, or nil to keep the pack's own palette. A sprite is
    /// recolored only when the pack names `accentInks` and the session chose its accent (`--accent`),
    /// see `PetSession.chosenAccent`. An accent `on` only filled from the pack keeps the palette.
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

    /// The palette with the accent inks repainted. An ink the palette does not hold stays transparent.
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
            colorsByCharacter: colorsByCharacter(sheet.colorsByCharacter, inks: inks, accent: accent)
        )
    }
}
