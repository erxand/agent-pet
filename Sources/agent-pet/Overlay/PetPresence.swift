import AgentPetCore
import AppKit

final class PetPresence: LaneWalker {
    let sessionId: String
    let window: PetWindow
    let view: PetView
    let animator: PetAnimator

    var homeHorizontalCenter: CGFloat = 0
    var focusRequest: FocusRequest?
    var memberSessionIds: [String] = []
    var spritePackName: String
    var spriteSheet: SpriteSheet
    var spriteTint: AccentColor?
    var spaceMotion: SpaceMotion?
    var walksHomeFromSpace = false
    var groundIndex = -1
    var groundBody: GroundBody?
    var waitsOnJump = false

    var laneWidth: CGFloat { view.contentSize.width }
    var windowWidth: CGFloat { view.preferredSize.width }
    var isInFlight: Bool { spaceMotion != nil }

    var shownAnimationName: SpriteAnimationName {
        spaceMotion?.animationName ?? groundBodyAnimationName ?? animator.animationName
    }

    var groundBodyFrameIndex: Int? {
        guard spaceMotion == nil, animator.isGrounded else { return nil }
        return groundBody?.frameIndex
    }

    private var groundBodyAnimationName: SpriteAnimationName? {
        guard animator.isGrounded else { return nil }
        return groundBody?.animationName
    }

    var shownFacingLeft: Bool {
        spaceMotion?.facingLeft ?? animator.facingLeft
    }

    init(
        sessionId: String,
        window: PetWindow,
        view: PetView,
        spritePackName: String,
        spriteSheet: SpriteSheet,
        animator: PetAnimator = PetAnimator()
    ) {
        self.animator = animator
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
