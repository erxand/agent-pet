import AppKit
import Foundation

package struct SpritePackLoader {
    package static let defaultPackName = "claude"

    private static let manifestFileName = "pack.json"
    private static let hexPrefix = "#"
    private static let hexDigitCount = 6
    private static let hexRadix = 16
    private static let lineSeparator: Character = "\n"
    private static let carriageReturn = "\r"

    package struct LoadedSpritePack {
        let sheet: SpriteSheet
        let declaredAccent: AccentColor?
        let unknownAccentName: String?
    }

    package enum LoadOutcome {
        case loaded(LoadedSpritePack)
        case failed(reason: String)
    }

    private let packsDirectory: URL
    private let fileManager = FileManager.default

    package init(packsDirectory: URL = PetPaths.spritesDirectory) {
        self.packsDirectory = packsDirectory
    }

    package func availablePackNames() -> [String] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: packsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }
        return entries
            .filter { entryURL in isDirectory(entryURL) }
            .map { entryURL in entryURL.lastPathComponent }
            .sorted()
    }

    package func directoryModification(forPackNamed packName: String) -> Date? {
        let attributes = try? fileManager.attributesOfItem(atPath: directory(forPackNamed: packName).path)
        return attributes?[.modificationDate] as? Date
    }

    package func load(packNamed packName: String) -> LoadOutcome {
        let packDirectory = directory(forPackNamed: packName)
        guard let manifestData = try? Data(contentsOf: packDirectory.appendingPathComponent(SpritePackLoader.manifestFileName)) else {
            return .failed(reason: "missing \(SpritePackLoader.manifestFileName)")
        }
        guard let manifest = try? JSONDecoder().decode(SpritePackManifest.self, from: manifestData) else {
            return .failed(reason: "unreadable \(SpritePackLoader.manifestFileName)")
        }
        let frameSize = manifest.frameSize ?? PixelFrame.fallbackSideLength
        guard frameSize > 0 else { return .failed(reason: "frameSize must be positive") }

        var framesByAnimation: [SpriteAnimationName: [PixelFrame]] = [:]
        for animationName in SpriteAnimationName.allCases {
            let animationURL = packDirectory.appendingPathComponent(animationName.packFileName)
            guard let animationText = try? String(contentsOf: animationURL, encoding: .utf8) else {
                guard animationName.isOptionalInPack else {
                    return .failed(reason: "missing \(animationName.packFileName)")
                }
                framesByAnimation[animationName] = []
                continue
            }
            guard let frames = SpritePackLoader.parseFrames(from: animationText, frameSize: frameSize) else {
                return .failed(reason: "\(animationName.packFileName) is not \(frameSize) by \(frameSize) frames")
            }
            framesByAnimation[animationName] = frames
        }

        let colorsByCharacter = SpritePackLoader.parsePalette(manifest.palette)
        let sheet = SpriteSheet(
            idle: framesByAnimation[.idle] ?? [],
            walk: framesByAnimation[.walk] ?? [],
            wave: framesByAnimation[.wave] ?? [],
            sit: framesByAnimation[.sit] ?? [],
            emerge: framesByAnimation[.emerge] ?? [],
            dive: framesByAnimation[.dive] ?? [],
            colorsByCharacter: colorsByCharacter
        )
        let declaredAccent = manifest.accent.flatMap { accentName in AccentColor(rawValue: accentName) }
        let unknownAccentName = declaredAccent == nil ? manifest.accent : nil
        return .loaded(
            LoadedSpritePack(sheet: sheet, declaredAccent: declaredAccent, unknownAccentName: unknownAccentName)
        )
    }

    private func directory(forPackNamed packName: String) -> URL {
        packsDirectory.appendingPathComponent(packName, isDirectory: true)
    }

    private func isDirectory(_ entryURL: URL) -> Bool {
        let values = try? entryURL.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory ?? false
    }

    private struct SpritePackManifest: Codable {
        let name: String?
        let frameSize: Int?
        let palette: [String: String]?
        let accent: String?
    }

    private static func parseFrames(from text: String, frameSize: Int) -> [PixelFrame]? {
        var frames: [PixelFrame] = []
        var pendingRows: [String] = []
        let lines = text.split(separator: lineSeparator, omittingEmptySubsequences: false)

        for line in lines {
            let cleanedLine = String(line).replacingOccurrences(of: carriageReturn, with: "")
            if cleanedLine.trimmingCharacters(in: .whitespaces).isEmpty {
                guard !pendingRows.isEmpty else { continue }
                guard let frame = makeFrame(rows: pendingRows, frameSize: frameSize) else { return nil }
                frames.append(frame)
                pendingRows = []
                continue
            }
            pendingRows.append(cleanedLine)
        }

        if !pendingRows.isEmpty {
            guard let frame = makeFrame(rows: pendingRows, frameSize: frameSize) else { return nil }
            frames.append(frame)
        }

        return frames.isEmpty ? nil : frames
    }

    private static func makeFrame(rows: [String], frameSize: Int) -> PixelFrame? {
        guard rows.count == frameSize else { return nil }
        guard rows.allSatisfy({ row in row.count == frameSize }) else { return nil }
        return PixelFrame(rows)
    }

    private static func parsePalette(_ rawPalette: [String: String]?) -> [Character: NSColor] {
        guard let rawPalette else { return SpritePalette.defaultColorsByCharacter }
        var colorsByCharacter: [Character: NSColor] = [:]
        for (rawCharacter, rawColor) in rawPalette {
            guard rawCharacter.count == 1, let inkCharacter = rawCharacter.first else { continue }
            guard let parsedColor = parseColor(hexText: rawColor) else { continue }
            colorsByCharacter[inkCharacter] = parsedColor
        }
        return colorsByCharacter.isEmpty ? SpritePalette.defaultColorsByCharacter : colorsByCharacter
    }

    private static func parseColor(hexText: String) -> NSColor? {
        var digits = hexText.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix(hexPrefix) { digits.removeFirst() }
        guard digits.count == hexDigitCount, let packedValue = UInt32(digits, radix: hexRadix) else { return nil }
        return NSColor(hex: packedValue)
    }
}
