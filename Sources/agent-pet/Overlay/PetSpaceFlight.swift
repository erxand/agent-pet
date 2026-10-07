import AgentPetCore
import AppKit

enum PetSpaceFlight {
    static func advance(
        _ presence: PetPresence,
        elapsedSeconds: Double,
        floats: Bool,
        screenFrame: CGRect,
        groundBottom: CGFloat,
        homeCenterX: CGFloat,
        render: (PetPresence) -> Void,
        landed: (PetPresence) -> Void = { _ in }
    ) -> Bool {
        guard !presence.animator.isDiving, !presence.animator.isSubmerged else {
            leave(presence)
            return false
        }
        if presence.spaceMotion == nil {
            guard floats, presence.animator.isGrounded else { return false }
            let frame = presence.window.frame
            presence.spaceMotion = SpaceMotion(
                launchingFrom: CGPoint(x: frame.midX, y: frame.minY + presence.view.contentSize.height / 2),
                seed: SpaceMotion.seed(forPetKey: presence.sessionId),
                facingLeft: presence.animator.facingLeft
            )
            presence.view.update(spaceRotationInRadians: 0)
        }
        guard var motion = presence.spaceMotion else { return false }
        if !floats { motion.returnToGround() }
        motion.advance(
            elapsedSeconds: elapsedSeconds,
            area: area(for: presence, screenFrame: screenFrame, groundBottom: groundBottom),
            homeCenterX: homeCenterX
        )
        guard !motion.isOnGround else {
            presence.spaceMotion = nil
            presence.view.update(spaceRotationInRadians: nil)
            presence.animator.resumeGrounded(horizontalOffsetFromHome: motion.center.x - homeCenterX)
            landed(presence)
            return false
        }
        presence.spaceMotion = motion
        presence.animator.advanceInSpace(elapsedSeconds: elapsedSeconds)
        presence.view.update(spaceRotationInRadians: CGFloat(motion.rotationInRadians))
        render(presence)
        place(presence, center: motion.center)
        return true
    }

    static func leave(_ presence: PetPresence) {
        guard let motion = presence.spaceMotion else { return }
        presence.spaceMotion = nil
        presence.view.update(spaceRotationInRadians: nil)
        place(presence, center: motion.center)
    }

    static func area(for presence: PetPresence, screenFrame: CGRect, groundBottom: CGFloat) -> SpaceArea {
        let halfSide = presence.view.preferredSize.width / 2
        return SpaceArea(
            lowestCenter: CGPoint(x: screenFrame.minX + halfSide, y: groundBottom + presence.view.contentSize.height / 2),
            highestCenter: CGPoint(x: screenFrame.maxX - halfSide, y: screenFrame.maxY - halfSide)
        )
    }

    private static func place(_ presence: PetPresence, center: CGPoint) {
        let size = presence.view.preferredSize
        let frame = CGRect(
            x: (center.x - size.width / 2).rounded(),
            y: (center.y - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
        guard frame != presence.window.frame else { return }
        presence.window.setFrame(frame, display: false)
    }
}
