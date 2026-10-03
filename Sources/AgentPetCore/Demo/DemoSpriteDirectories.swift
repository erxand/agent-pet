import Foundation

package enum DemoSpriteDirectories {
    private static let shippedSpritesDirectoryName = "sprites"
    private static let markerPackName = SpritePackLoader.defaultPackName
    private static let markerFileName = "pack.json"
    private static let maximumParentLevels = 5

    package static func shippedSpritesDirectory(executablePath: String?) -> URL? {
        guard let executablePath else { return nil }
        var directory = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<maximumParentLevels {
            let candidate = directory.appendingPathComponent(shippedSpritesDirectoryName, isDirectory: true)
            let marker = candidate
                .appendingPathComponent(markerPackName, isDirectory: true)
                .appendingPathComponent(markerFileName)
            if FileManager.default.fileExists(atPath: marker.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        return nil
    }
}
