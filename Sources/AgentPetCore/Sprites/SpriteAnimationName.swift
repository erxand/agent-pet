package enum SpriteAnimationName: String, CaseIterable, Hashable {
    case idle
    case walk
    case wave
    case sit
    case emerge
    case dive
    case jump
    case fall

    private static let textFileExtension = "txt"

    package var packFileName: String {
        "\(rawValue).\(SpriteAnimationName.textFileExtension)"
    }

    package var isOptionalInPack: Bool {
        switch self {
        case .idle, .walk, .wave, .sit: return false
        case .emerge, .dive, .jump, .fall: return true
        }
    }

    package var standIn: SpriteAnimationName? {
        switch self {
        case .jump: return .walk
        case .fall: return .idle
        case .idle, .walk, .wave, .sit, .emerge, .dive: return nil
        }
    }

    package func shown(in sheet: SpriteSheet) -> SpriteAnimationName? {
        if !frames(in: sheet).isEmpty { return self }
        if let standIn, !standIn.frames(in: sheet).isEmpty { return standIn }
        return SpriteAnimationName.allCases.first { animationName in !animationName.frames(in: sheet).isEmpty }
    }

    package func frames(in sheet: SpriteSheet) -> [PixelFrame] {
        switch self {
        case .idle: return sheet.idle
        case .walk: return sheet.walk
        case .wave: return sheet.wave
        case .sit: return sheet.sit
        case .emerge: return sheet.emerge
        case .dive: return sheet.dive
        case .jump: return sheet.jump
        case .fall: return sheet.fall
        }
    }
}
