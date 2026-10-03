import AppKit

enum PackAccentResolver {
    private static let excludedDarkestColorCount = 2
    private static let redLuminanceWeight: CGFloat = 0.2126
    private static let greenLuminanceWeight: CGFloat = 0.7152
    private static let blueLuminanceWeight: CGFloat = 0.0722

    private struct ColorComponents {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        var luminance: CGFloat {
            red * PackAccentResolver.redLuminanceWeight
                + green * PackAccentResolver.greenLuminanceWeight
                + blue * PackAccentResolver.blueLuminanceWeight
        }

        func squaredDistance(to other: ColorComponents) -> CGFloat {
            let redDifference = red - other.red
            let greenDifference = green - other.green
            let blueDifference = blue - other.blue
            return redDifference * redDifference
                + greenDifference * greenDifference
                + blueDifference * blueDifference
        }
    }

    static func dominantAccent(colorsByCharacter: [Character: NSColor], frames: [PixelFrame]) -> AccentColor? {
        let componentsByCharacter = colorsByCharacter.compactMapValues { color in components(of: color) }
        let candidates = candidateCharacters(componentsByCharacter: componentsByCharacter)
        let occurrenceCountByCharacter = occurrenceCounts(of: Set(candidates), in: frames)
        let usedCandidates = candidates.filter { character in (occurrenceCountByCharacter[character] ?? 0) > 0 }
        guard let dominantCharacter = usedCandidates.max(by: { leftCharacter, rightCharacter in
            (occurrenceCountByCharacter[leftCharacter] ?? 0) < (occurrenceCountByCharacter[rightCharacter] ?? 0)
        }), let dominantComponents = componentsByCharacter[dominantCharacter] else { return nil }
        return nearestAccent(to: dominantComponents)
    }

    private static func candidateCharacters(componentsByCharacter: [Character: ColorComponents]) -> [Character] {
        let charactersFromDarkest = componentsByCharacter.keys.sorted { leftCharacter, rightCharacter in
            let leftLuminance = componentsByCharacter[leftCharacter]?.luminance ?? 0
            let rightLuminance = componentsByCharacter[rightCharacter]?.luminance ?? 0
            if leftLuminance == rightLuminance { return leftCharacter < rightCharacter }
            return leftLuminance < rightLuminance
        }
        let lighterCharacters = Array(charactersFromDarkest.dropFirst(excludedDarkestColorCount))
        let candidates = lighterCharacters.isEmpty ? charactersFromDarkest : lighterCharacters
        return candidates.sorted()
    }

    private static func occurrenceCounts(of characters: Set<Character>, in frames: [PixelFrame]) -> [Character: Int] {
        var occurrenceCountByCharacter: [Character: Int] = [:]
        for frame in frames {
            for row in frame.rows {
                for character in row where characters.contains(character) {
                    occurrenceCountByCharacter[character, default: 0] += 1
                }
            }
        }
        return occurrenceCountByCharacter
    }

    private static func nearestAccent(to target: ColorComponents) -> AccentColor? {
        AccentColor.allCases.min { leftAccent, rightAccent in
            accentDistance(leftAccent, to: target) < accentDistance(rightAccent, to: target)
        }
    }

    private static func accentDistance(_ accent: AccentColor, to target: ColorComponents) -> CGFloat {
        guard let accentComponents = components(of: accent.color) else { return .greatestFiniteMagnitude }
        return accentComponents.squaredDistance(to: target)
    }

    private static func components(of color: NSColor) -> ColorComponents? {
        guard let standardColor = color.usingColorSpace(.sRGB) else { return nil }
        return ColorComponents(
            red: standardColor.redComponent,
            green: standardColor.greenComponent,
            blue: standardColor.blueComponent
        )
    }
}
