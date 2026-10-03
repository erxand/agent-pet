import Foundation

package protocol SpriteStrategy {
    func spriteName(forNewSessionId sessionId: String) -> String?
}

package struct LeastUsedSpriteStrategy: SpriteStrategy {
    private let sessionSource: SessionSource
    private let loader: SpritePackLoader

    package init(sessionSource: SessionSource, loader: SpritePackLoader = SpritePackLoader()) {
        self.sessionSource = sessionSource
        self.loader = loader
    }

    package func spriteName(forNewSessionId sessionId: String) -> String? {
        SpritePackAssignment.current(
            excludingSessionId: sessionId,
            sessionSource: sessionSource,
            loader: loader
        ).pickLeastUsedPackName()
    }
}
