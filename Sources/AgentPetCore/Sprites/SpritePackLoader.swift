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
    private let extraDirectoryPaths: [String]
    private let homeDirectory: URL
    private let fileManager = FileManager.default

    /// `packsDirectory` is `~/.agent-pet/sprites`. `extraDirectoryPaths` are the config's
    /// `spriteDirectories`, searched after it in order; the first folder that holds a pack name wins.
    package init(
        packsDirectory: URL = PetPaths.spritesDirectory,
        extraDirectoryPaths: [String] = ConfigurationFile.load().spriteDirectories,
        homeDirectory: URL = PetPaths.homeDirectory
    ) {
        self.packsDirectory = packsDirectory
        self.extraDirectoryPaths = extraDirectoryPaths
        self.homeDirectory = homeDirectory
    }

    package func availablePackNames() -> [String] {
        scan().directoryByPackName.keys.sorted()
    }

    /// Every loadable pack name and the folder it is read from, after the clash rule.
    package func packDirectoriesByName() -> [String: URL] {
        scan().directoryByPackName
    }

    /// Problems with the extra folders: a folder that is missing or unreadable, and a pack name that
    /// an earlier folder already holds. Each is one log line; the caller decides how often to say it.
    package func directoryIssues() -> [String] {
        scan().issues
    }

    package func directory(forPackNamed packName: String) -> URL {
        scan(lookingFor: packName).directoryByPackName[packName]
            ?? packsDirectory.appendingPathComponent(packName, isDirectory: true)
    }

    package func directoryModification(forPackNamed packName: String) -> Date? {
        SpritePackLoader.modification(of: directory(forPackNamed: packName))
    }

    package static func modification(of directoryURL: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: directoryURL.path)
        return attributes?[.modificationDate] as? Date
    }

    private struct Scan {
        var directoryByPackName: [String: URL] = [:]
        var issues: [String] = []
    }

    private func scan(lookingFor wantedPackName: String? = nil) -> Scan {
        var result = Scan()
        var seenRootPaths: Set<String> = []
        for (rootIndex, root) in searchRoots().enumerated() {
            if let rootURL = root.url, !seenRootPaths.insert(rootURL.standardizedFileURL.path).inserted { continue }
            guard let rootURL = root.url, let entries = try? fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey]
            ) else {
                if rootIndex > 0 {
                    result.issues.append("agent-pet: sprite directory \(root.configuredPath) is missing or unreadable, skipped")
                }
                continue
            }
            for entryURL in entries.sorted(by: { first, second in first.lastPathComponent < second.lastPathComponent })
            where isDirectory(entryURL) {
                let packName = entryURL.lastPathComponent
                if let winner = result.directoryByPackName[packName] {
                    result.issues.append(
                        "agent-pet: sprite pack \(packName) in \(root.configuredPath) is ignored, \(winner.path) has the same name"
                    )
                    continue
                }
                result.directoryByPackName[packName] = entryURL
                if packName == wantedPackName { return result }
            }
        }
        return result
    }

    private struct SearchRoot {
        let url: URL?
        let configuredPath: String
    }

    private func searchRoots() -> [SearchRoot] {
        var roots = [SearchRoot(url: packsDirectory, configuredPath: packsDirectory.path)]
        for configuredPath in extraDirectoryPaths {
            let expanded = SessionDirectoryPattern.expand(configuredPath, homeDirectory: homeDirectory)
            if expanded.isEmpty {
                roots.append(SearchRoot(url: nil, configuredPath: configuredPath))
                continue
            }
            roots += expanded.map { url in SearchRoot(url: url, configuredPath: configuredPath) }
        }
        return roots
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
