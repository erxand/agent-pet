import Foundation

package protocol SpriteStrategy {
    func spriteName(forNewSessionId sessionId: String, group: String?) -> String?
}

package struct LeastUsedSpriteStrategy: SpriteStrategy {
    private let sessionSource: SessionSource
    private let loader: SpritePackLoader
    private let reservedPackNames: Set<String>

    package init(
        sessionSource: SessionSource,
        loader: SpritePackLoader = SpritePackLoader(),
        reservedPackNames: [String] = []
    ) {
        self.sessionSource = sessionSource
        self.loader = loader
        self.reservedPackNames = Set(reservedPackNames)
    }

    package func spriteName(forNewSessionId sessionId: String, group: String?) -> String? {
        let assignment = SpritePackAssignment.current(
            excludingSessionId: sessionId,
            sessionSource: sessionSource,
            loader: loader,
            reservedPackNames: reservedPackNames
        )
        if let group, let ownerSprite = assignment.spriteOfLivePet(petKey: group) {
            return ownerSprite
        }
        return assignment.pickLeastUsedPackName()
    }
}
