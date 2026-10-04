import Foundation

enum SpritePackAccent {
    static func accent(forPackNamed packName: String, loader: SpritePackLoader = SpritePackLoader()) -> AccentColor? {
        switch loader.load(packNamed: packName) {
        case .loaded(let pack):
            return pack.declaredAccent
                ?? PackAccentResolver.dominantAccent(
                    colorsByCharacter: pack.sheet.colorsByCharacter,
                    frames: everyFrame(in: pack.sheet)
                )
        case .failed:
            return nil
        }
    }

    private static func everyFrame(in sheet: SpriteSheet) -> [PixelFrame] {
        SpriteAnimationName.allCases.flatMap { animationName in animationName.frames(in: sheet) }
    }
}
