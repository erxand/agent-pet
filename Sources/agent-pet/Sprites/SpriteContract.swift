import AppKit

enum PixelInk: Character, CaseIterable {
    case clear = "."
    case outline = "#"
    case body = "o"
    case bodyShade = "O"
    case eye = "e"
    case highlight = "w"
    case scarf = "A"
    case scarfShade = "a"
}

struct PixelFrame {
    static let fallbackSideLength = 16

    let rows: [String]
    let sideLength: Int

    private let characterGrid: [[Character]]

    init(_ rows: [String]) {
        precondition(!rows.isEmpty, "frame must have at least one row")
        let derivedSideLength = rows.count
        precondition(
            rows.allSatisfy { row in row.count == derivedSideLength },
            "frame must be square, got \(derivedSideLength) rows"
        )
        self.rows = rows
        self.sideLength = derivedSideLength
        self.characterGrid = rows.map { row in Array(row) }
    }

    func character(column: Int, row: Int) -> Character {
        characterGrid[row][column]
    }
}

struct SpriteSheet {
    let idle: [PixelFrame]
    let walk: [PixelFrame]
    let wave: [PixelFrame]
    let sit: [PixelFrame]
    let emerge: [PixelFrame]
    let dive: [PixelFrame]
    let frameSize: Int
    let colorsByCharacter: [Character: NSColor]

    init(
        idle: [PixelFrame],
        walk: [PixelFrame],
        wave: [PixelFrame],
        sit: [PixelFrame],
        emerge: [PixelFrame] = [],
        dive: [PixelFrame] = [],
        colorsByCharacter: [Character: NSColor] = SpritePalette.defaultColorsByCharacter
    ) {
        self.idle = idle
        self.walk = walk
        self.wave = wave
        self.sit = sit
        self.emerge = emerge
        self.dive = dive
        self.colorsByCharacter = colorsByCharacter
        self.frameSize = SpriteSheet.deriveFrameSize(
            idle: idle,
            walk: walk,
            wave: wave,
            sit: sit,
            emerge: emerge,
            dive: dive
        )
    }

    var palette: SpritePalette {
        SpritePalette(colorsByCharacter: colorsByCharacter)
    }

    private static func deriveFrameSize(
        idle: [PixelFrame],
        walk: [PixelFrame],
        wave: [PixelFrame],
        sit: [PixelFrame],
        emerge: [PixelFrame],
        dive: [PixelFrame]
    ) -> Int {
        let everyFrame = idle + walk + wave + sit + emerge + dive
        return everyFrame.first?.sideLength ?? PixelFrame.fallbackSideLength
    }
}

enum AccentColor: String, CaseIterable, Codable {
    case red
    case blue
    case green
    case yellow
    case purple
    case orange
    case pink
    case cyan

    var color: NSColor {
        switch self {
        case .red: return NSColor(hex: 0xFF5252)
        case .blue: return NSColor(hex: 0x4C8DFF)
        case .green: return NSColor(hex: 0x4ADE80)
        case .yellow: return NSColor(hex: 0xFFD93D)
        case .purple: return NSColor(hex: 0xA970FF)
        case .orange: return NSColor(hex: 0xFF9F1C)
        case .pink: return NSColor(hex: 0xFF7EB6)
        case .cyan: return NSColor(hex: 0x2EE6D6)
        }
    }

    static func derived(fromSessionId sessionId: String) -> AccentColor {
        let hash = fnv1a(sessionId)
        return allCases[Int(hash % UInt64(allCases.count))]
    }

    private static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

struct SpritePalette {
    static let body = NSColor(hex: 0xD97757)
    static let bodyShade = NSColor(hex: 0xB85C3E)
    static let outline = NSColor(hex: 0x3B2418)
    static let eye = NSColor(hex: 0x1A1A1A)
    static let highlight = NSColor(hex: 0xF5D0BF)
    static let scarf = NSColor(hex: 0x2EE6D6)
    static let scarfShade = NSColor(hex: 0x20A196)

    static let defaultColorsByCharacter: [Character: NSColor] = [
        PixelInk.outline.rawValue: SpritePalette.outline,
        PixelInk.body.rawValue: SpritePalette.body,
        PixelInk.bodyShade.rawValue: SpritePalette.bodyShade,
        PixelInk.eye.rawValue: SpritePalette.eye,
        PixelInk.highlight.rawValue: SpritePalette.highlight,
        PixelInk.scarf.rawValue: SpritePalette.scarf,
        PixelInk.scarfShade.rawValue: SpritePalette.scarfShade
    ]

    let colorsByCharacter: [Character: NSColor]

    init(colorsByCharacter: [Character: NSColor] = SpritePalette.defaultColorsByCharacter) {
        self.colorsByCharacter = colorsByCharacter
    }

    func color(for character: Character) -> NSColor? {
        if character == PixelInk.clear.rawValue { return nil }
        return colorsByCharacter[character]
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}
