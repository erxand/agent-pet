import AppKit

package enum PixelInk: Character, CaseIterable {
    case clear = "."
    case outline = "#"
    case body = "o"
    case bodyShade = "O"
    case eye = "e"
    case highlight = "w"
    case scarf = "A"
    case scarfShade = "a"
}

package struct PixelFrame {
    package static let fallbackSideLength = 16

    package let rows: [String]
    package let sideLength: Int

    private let characterGrid: [[Character]]

    package init(_ rows: [String]) {
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

    package func character(column: Int, row: Int) -> Character {
        characterGrid[row][column]
    }
}

package struct SpriteSheet {
    package let idle: [PixelFrame]
    package let walk: [PixelFrame]
    package let wave: [PixelFrame]
    package let sit: [PixelFrame]
    package let emerge: [PixelFrame]
    package let dive: [PixelFrame]
    package let jump: [PixelFrame]
    package let fall: [PixelFrame]
    package let highfive: [PixelFrame]
    package let frameSize: Int
    package let colorsByCharacter: [Character: NSColor]

    package init(
        idle: [PixelFrame],
        walk: [PixelFrame],
        wave: [PixelFrame],
        sit: [PixelFrame],
        emerge: [PixelFrame] = [],
        dive: [PixelFrame] = [],
        jump: [PixelFrame] = [],
        fall: [PixelFrame] = [],
        highfive: [PixelFrame] = [],
        colorsByCharacter: [Character: NSColor] = SpritePalette.defaultColorsByCharacter
    ) {
        self.idle = idle
        self.walk = walk
        self.wave = wave
        self.sit = sit
        self.emerge = emerge
        self.dive = dive
        self.jump = jump
        self.fall = fall
        self.highfive = highfive
        self.colorsByCharacter = colorsByCharacter
        self.frameSize = SpriteSheet.deriveFrameSize(
            idle: idle,
            walk: walk,
            wave: wave,
            sit: sit,
            emerge: emerge,
            dive: dive,
            jump: jump,
            fall: fall,
            highfive: highfive
        )
    }

    package var palette: SpritePalette {
        SpritePalette(colorsByCharacter: colorsByCharacter)
    }

    private static func deriveFrameSize(
        idle: [PixelFrame],
        walk: [PixelFrame],
        wave: [PixelFrame],
        sit: [PixelFrame],
        emerge: [PixelFrame],
        dive: [PixelFrame],
        jump: [PixelFrame],
        fall: [PixelFrame],
        highfive: [PixelFrame]
    ) -> Int {
        let everyFrame = idle + walk + wave + sit + emerge + dive + jump + fall + highfive
        return everyFrame.first?.sideLength ?? PixelFrame.fallbackSideLength
    }
}

package enum AccentColor: String, CaseIterable, Codable {
    case red
    case blue
    case green
    case yellow
    case purple
    case orange
    case pink
    case cyan

    package var color: NSColor {
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

    package static func derived(fromSessionId sessionId: String) -> AccentColor {
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

package struct SpritePalette {
    package static let body = NSColor(hex: 0xD97757)
    package static let bodyShade = NSColor(hex: 0xB85C3E)
    package static let outline = NSColor(hex: 0x3B2418)
    package static let eye = NSColor(hex: 0x1A1A1A)
    package static let highlight = NSColor(hex: 0xF5D0BF)
    package static let scarf = NSColor(hex: 0x2EE6D6)
    package static let scarfShade = NSColor(hex: 0x20A196)

    package static let defaultColorsByCharacter: [Character: NSColor] = [
        PixelInk.outline.rawValue: SpritePalette.outline,
        PixelInk.body.rawValue: SpritePalette.body,
        PixelInk.bodyShade.rawValue: SpritePalette.bodyShade,
        PixelInk.eye.rawValue: SpritePalette.eye,
        PixelInk.highlight.rawValue: SpritePalette.highlight,
        PixelInk.scarf.rawValue: SpritePalette.scarf,
        PixelInk.scarfShade.rawValue: SpritePalette.scarfShade
    ]

    package let colorsByCharacter: [Character: NSColor]

    package init(colorsByCharacter: [Character: NSColor] = SpritePalette.defaultColorsByCharacter) {
        self.colorsByCharacter = colorsByCharacter
    }

    package func color(for character: Character) -> NSColor? {
        if character == PixelInk.clear.rawValue { return nil }
        return colorsByCharacter[character]
    }
}

extension NSColor {
    package convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}
