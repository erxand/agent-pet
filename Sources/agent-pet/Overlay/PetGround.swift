import AgentPetCore
import AppKit

final class PetGround {
    private let makeDockGround: () -> DockGround
    private var dockGround: DockGround?
    private(set) var profile = GroundProfile.flat(base: PetGeometry.windowBottomInset)
    private(set) var previousProfile: GroundProfile?
    private var lastBottomInset: CGFloat?
    private(set) var visibleFrame = CGRect.zero

    var watchesTheDock: Bool { dockGround != nil }

    init(makeDockGround: @escaping () -> DockGround) {
        self.makeDockGround = makeDockGround
    }

    func refresh(
        standsOnDock: Bool,
        screenFrames: OverlayScreenFrames,
        now: TimeInterval,
        elapsedSeconds: Double?,
        bottomInset: CGFloat = PetGeometry.windowBottomInset
    ) {
        visibleFrame = screenFrames.visibleFrame
        let dockBar: CGRect?
        if !standsOnDock {
            dockGround = nil
            dockBar = nil
        } else if let elapsedSeconds {
            let watched = dockGround ?? makeDockGround()
            dockGround = watched
            dockBar = watched.bar(now: now, elapsedSeconds: elapsedSeconds)
        } else {
            dockBar = dockGround?.lastBar
        }
        if elapsedSeconds != nil { previousProfile = bottomInset == lastBottomInset ? profile : nil }
        lastBottomInset = bottomInset
        profile = GroundProfile.resolve(
            standsOnDock: standsOnDock,
            screenFrame: screenFrames.screenFrame,
            visibleFrame: screenFrames.visibleFrame,
            dockBar: dockBar,
            dockRestingTop: standsOnDock ? dockGround?.lastRestingTop : nil,
            bottomInset: bottomInset
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
        let here = standingCenter(of: presence, desiredCenter: presence.homeHorizontalCenter + presence.animator.horizontalOffsetFromHome)
        let allowed = body.allowsStep(
            toGround: profile.height(over: bodySpan(of: presence, centerX: center)),
            from: profile.height(over: bodySpan(of: presence, centerX: here))
        )
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
            elapsedSeconds: elapsedSeconds,
            previousProfile: elapsedSeconds > 0 && previousProfile?.kind == .dock ? previousProfile : nil
        )
    }
}
