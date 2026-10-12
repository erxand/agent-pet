import CoreGraphics
import Foundation

/// A pet being drawn into the Dock: a short wind-up away from the tile, then a
/// pull toward it that speeds up, the pet spinning on its own axis, circling a
/// tight spiral around its path and shrinking as it goes. The spiral never
/// strays more than `maximumSwirlRadius` from the straight line, and with
/// `bounds` the visible pet never leaves the screen.
package struct WhirlpoolMotion: Equatable {
    package static let durationInSeconds: Double = 0.9
    package static let windUpShare: Double = 0.18
    package static let windUpDistance: Double = 10
    package static let windUpScale: Double = 1.08
    package static let spins: Double = 3
    package static let swirlTurns: Double = 2
    package static let maximumSwirlRadius: Double = 28
    package static let aimFollowRatePerSecond: Double = 6
    package static let smallestScale: Double = 0.05

    package let start: CGPoint
    package private(set) var target: CGPoint
    package private(set) var aim: CGPoint
    package private(set) var elapsedSeconds: Double = 0
    package let bounds: CGRect?
    package let halfExtent: CGFloat
    private let turnDirection: Double

    /// `bounds` is the screen the pet must stay on, and `halfExtent` half the
    /// pet's drawn size at full scale, so the clamp keeps the whole sprite in.
    package init(from start: CGPoint, toward target: CGPoint, bounds: CGRect? = nil, halfExtent: CGFloat = 0) {
        self.start = start
        self.target = target
        self.bounds = bounds
        self.halfExtent = halfExtent
        aim = target
        turnDirection = start.x <= target.x ? -1 : 1
    }

    package var progress: Double { min(max(elapsedSeconds / WhirlpoolMotion.durationInSeconds, 0), 1) }

    package var isFinished: Bool { elapsedSeconds >= WhirlpoolMotion.durationInSeconds }

    /// 0 through the wind-up, then 0 to 1 with a cubic ease-in.
    package var easedProgress: Double {
        let pull = max(0, progress - WhirlpoolMotion.windUpShare) / (1 - WhirlpoolMotion.windUpShare)
        return pull * pull * pull
    }

    /// 0 to 1 to 0 across the wind-up.
    private var windUp: Double {
        guard progress < WhirlpoolMotion.windUpShare else { return 0 }
        return sin(Double.pi * progress / WhirlpoolMotion.windUpShare)
    }

    package var center: CGPoint {
        let pull = easedProgress
        let dx = Double(aim.x - start.x), dy = Double(aim.y - start.y)
        let distance = max(hypot(dx, dy), 0.001)
        let away = (x: -dx / distance, y: -dy / distance)
        let lift = WhirlpoolMotion.windUpDistance * windUp
        let radius = min(WhirlpoolMotion.maximumSwirlRadius, distance * 0.12) * sin(Double.pi * pull)
        let angle = turnDirection * WhirlpoolMotion.swirlTurns * 2 * Double.pi * pull
        var point = CGPoint(
            x: Double(start.x) + dx * pull + away.x * lift + radius * cos(angle),
            y: Double(start.y) + dy * pull + away.y * lift + radius * sin(angle)
        )
        if let bounds {
            let inset = halfExtent * CGFloat(scale)
            let inner = bounds.insetBy(dx: min(inset, bounds.width / 2), dy: min(inset, bounds.height / 2))
            point.x = min(max(point.x, inner.minX), inner.maxX)
            point.y = min(max(point.y, inner.minY), inner.maxY)
        }
        return point
    }

    package var rotationInRadians: Double {
        let spinUp = progress * progress
        return turnDirection * WhirlpoolMotion.spins * 2 * Double.pi * spinUp
    }

    package var scale: Double {
        if progress < WhirlpoolMotion.windUpShare { return 1 + (WhirlpoolMotion.windUpScale - 1) * windUp }
        return max(WhirlpoolMotion.smallestScale, 1 - easedProgress)
    }

    /// Fully visible until the last stretch, then gone as it reaches the tile.
    package var opacity: Double {
        let fade = max(0, easedProgress - 0.6) / 0.4
        return 1 - fade
    }

    package mutating func retarget(_ newTarget: CGPoint) {
        target = newTarget
    }

    package mutating func advance(elapsedSeconds step: Double) {
        guard step > 0 else { return }
        elapsedSeconds += step
        let follow = CGFloat(1 - exp(-WhirlpoolMotion.aimFollowRatePerSecond * step))
        aim = CGPoint(x: aim.x + (target.x - aim.x) * follow, y: aim.y + (target.y - aim.y) * follow)
        if isFinished { aim = target }
    }
}
