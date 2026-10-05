package enum SpriteAnimationName: String, CaseIterable, Hashable {
    case idle
    case walk
    case wave
    case sit
    case emerge
    case dive

    private static let textFileExtension = "txt"

    package var packFileName: String {
        "\(rawValue).\(SpriteAnimationName.textFileExtension)"
    }

    package var isOptionalInPack: Bool {
        switch self {
        case .idle, .walk, .wave, .sit: return false
        case .emerge, .dive: return true
        }
    }

    package func frames(in sheet: SpriteSheet) -> [PixelFrame] {
        switch self {
        case .idle: return sheet.idle
        case .walk: return sheet.walk
        case .wave: return sheet.wave
        case .sit: return sheet.sit
        case .emerge: return sheet.emerge
        case .dive: return sheet.dive
        }
    }
}
