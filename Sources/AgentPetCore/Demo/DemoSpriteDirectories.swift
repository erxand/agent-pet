import Foundation

package enum DemoSpriteDirectories {
    private static let markerPackName = SpritePackLoader.defaultPackName
    private static let maximumParentLevels = 5

    package static func shippedSpritesDirectory(executablePath: String?) -> URL? {
        guard let executablePath else { return nil }
        var directory = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<maximumParentLevels {
            let candidate = directory.appendingPathComponent(PetPaths.spritesDirectoryName, isDirectory: true)
            let marker = candidate
                .appendingPathComponent(markerPackName, isDirectory: true)
                .appendingPathComponent(SpritePackLoader.manifestFileName)
            if FileManager.default.fileExists(atPath: marker.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        return nil
    }
}
