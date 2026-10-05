import AgentPetCore
import AppKit

final class PetPresence {
    let sessionId: String
    let window: PetWindow
    let view: PetView
    let animator = PetAnimator()

    var homeHorizontalCenter: CGFloat = 0
    var focusRequest: FocusRequest?
    var memberSessionIds: [String] = []
    var spritePackName: String
    var spriteSheet: SpriteSheet
    var spriteTint: AccentColor?

    init(
        sessionId: String,
        window: PetWindow,
        view: PetView,
        spritePackName: String,
        spriteSheet: SpriteSheet
    ) {
        self.sessionId = sessionId
        self.window = window
        self.view = view
        self.spritePackName = spritePackName
        self.spriteSheet = spriteSheet
    }
}

struct SpriteImageCacheKey: Hashable {
    let packName: String
    let tint: AccentColor?
    let animationName: SpriteAnimationName
    let frameIndex: Int
    let facingLeft: Bool
}
