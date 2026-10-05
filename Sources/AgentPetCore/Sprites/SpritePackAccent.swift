import Foundation

enum SpritePackAccent {
    static func accent(forPackNamed packName: String, loader: SpritePackLoader = SpritePackLoader()) -> AccentColor? {
        accent(in: loader.load(packNamed: packName), loader: loader)
    }

    static func accent(in outcome: SpritePackLoader.LoadOutcome, loader: SpritePackLoader) -> AccentColor? {
        switch outcome {
        case .loaded(let pack):
            return pack.ownAccent
        case .failed:
            return nil
        case .notDownloaded(let undownloaded):
            loader.residency.requestDownload(undownloaded)
            return nil
        }
    }
}
