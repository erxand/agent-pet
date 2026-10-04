import Foundation

enum SpritePackAccent {
    static func accent(forPackNamed packName: String, loader: SpritePackLoader = SpritePackLoader()) -> AccentColor? {
        switch loader.load(packNamed: packName) {
        case .loaded(let pack):
            return pack.ownAccent
        case .failed:
            return nil
        }
    }
}
