import AgentPetCore
import AppKit

final class PetSpriteFrames {
    private static let substituteGroundFrameIndex = 0

    private var spriteImageCache: [SpriteImageCacheKey: NSImage] = [:]

    func removeAllCachedImages() {
        spriteImageCache.removeAll()
    }

    func image(for presence: PetPresence) -> NSImage? {
        guard let resolvedAnimation = resolveAnimation(
            presence.shownAnimationName,
            in: presence.spriteSheet
        ) else { return nil }

        let frameIndex = frameIndex(for: presence, resolvedAnimation: resolvedAnimation)
        let cacheKey = SpriteImageCacheKey(
            packName: presence.spritePackName,
            tint: presence.spriteTint,
            animationName: resolvedAnimation.animationName,
            frameIndex: frameIndex,
            facingLeft: presence.shownFacingLeft
        )

        if let cachedImage = spriteImageCache[cacheKey] {
            return cachedImage
        }
        let spriteImage = PixelRenderer.image(
            for: resolvedAnimation.frames[frameIndex],
            palette: presence.spriteSheet.palette,
            scale: PetGeometry.spriteScale,
            facingLeft: presence.shownFacingLeft
        )
        spriteImageCache[cacheKey] = spriteImage
        return spriteImage
    }

    private func frameIndex(for presence: PetPresence, resolvedAnimation: ResolvedAnimation) -> Int {
        let frameCount = resolvedAnimation.frames.count
        guard presence.animator.playsGroundAnimationOnce else {
            return presence.animator.frameTick % frameCount
        }
        guard resolvedAnimation.animationName == presence.shownAnimationName else {
            return PetSpriteFrames.substituteGroundFrameIndex
        }
        let spreadIndex = Int(presence.animator.groundAnimationProgress * Double(frameCount))
        return min(frameCount - 1, max(0, spreadIndex))
    }

    private struct ResolvedAnimation {
        let animationName: SpriteAnimationName
        let frames: [PixelFrame]
    }

    private func resolveAnimation(
        _ requestedAnimation: SpriteAnimationName,
        in spriteSheet: SpriteSheet
    ) -> ResolvedAnimation? {
        let requestedFrames = requestedAnimation.frames(in: spriteSheet)
        if !requestedFrames.isEmpty {
            return ResolvedAnimation(animationName: requestedAnimation, frames: requestedFrames)
        }
        for fallbackAnimation in SpriteAnimationName.allCases {
            let fallbackFrames = fallbackAnimation.frames(in: spriteSheet)
            if !fallbackFrames.isEmpty {
                return ResolvedAnimation(animationName: fallbackAnimation, frames: fallbackFrames)
            }
        }
        return nil
    }
}
