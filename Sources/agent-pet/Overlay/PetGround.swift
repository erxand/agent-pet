import AgentPetCore
import AppKit

final class PetGround {
    private let dockGround: DockGround
    private(set) var profile = GroundProfile.flat(base: PetGeometry.windowBottomInset)
    private(set) var visibleFrame = CGRect.zero

    init(dockGround: DockGround) {
        self.dockGround = dockGround
    }

    func refresh(standsOnDock: Bool, screenFrames: OverlayScreenFrames, now: TimeInterval, elapsedSeconds: Double?) {
        visibleFrame = screenFrames.visibleFrame
        let dockBar: CGRect?
        if !standsOnDock {
            dockBar = nil
        } else if let elapsedSeconds {
            dockBar = dockGround.bar(now: now, elapsedSeconds: elapsedSeconds)
        } else {
            dockBar = dockGround.lastBar
        }
        profile = GroundProfile.resolve(
            standsOnDock: standsOnDock,
            screenFrame: screenFrames.screenFrame,
            visibleFrame: screenFrames.visibleFrame,
            dockBar: dockBar,
            bottomInset: PetGeometry.windowBottomInset
        )
    }

    static func horizontalOrigin(desiredCenter: CGFloat, windowWidth: CGFloat, visibleFrame: CGRect) -> CGFloat {
        min(
            max(desiredCenter - windowWidth / 2, visibleFrame.minX),
            max(visibleFrame.maxX - windowWidth, visibleFrame.minX)
        )
    }

    func standingCenter(of presence: PetPresence, desiredCenter: CGFloat) -> CGFloat {
        let windowWidth = presence.view.preferredSize.width
        return PetGround.horizontalOrigin(desiredCenter: desiredCenter, windowWidth: windowWidth, visibleFrame: visibleFrame)
            + windowWidth / 2
    }

    func bodySpan(of presence: PetPresence, centerX: CGFloat) -> ClosedRange<CGFloat> {
        GroundProfile.bodySpan(
            centerX: centerX,
            spriteSideLength: presence.view.petAppearance.spriteSideLength,
            bodyWidthFraction: LaneLayout.bodyWidthFraction
        )
    }

    func allowsStep(_ presence: PetPresence, toOffset offset: CGFloat) -> Bool {
        guard profile.kind == .dock, var body = presence.groundBody else { return true }
        let center = standingCenter(of: presence, desiredCenter: presence.homeHorizontalCenter + offset)
        let allowed = body.allowsStep(toGround: profile.height(over: bodySpan(of: presence, centerX: center)))
        presence.groundBody = body
        if !allowed && body.isJumping { presence.waitsOnJump = true }
        return allowed
    }

    func finishStep(_ presence: PetPresence) {
        guard presence.waitsOnJump else { return }
        presence.waitsOnJump = false
        presence.animator.forgetBlockedWalk()
    }

    func floorUnderFlight(of presence: PetPresence) -> CGFloat {
        profile.height(over: bodySpan(of: presence, centerX: presence.window.frame.midX))
    }

    func windowBottom(for presence: PetPresence, standingCenter center: CGFloat, elapsedSeconds: Double) -> CGFloat {
        GroundPlacement.windowBottom(
            body: &presence.groundBody,
            profile: profile,
            span: bodySpan(of: presence, centerX: center),
            elapsedSeconds: elapsedSeconds
        )
    }
}
