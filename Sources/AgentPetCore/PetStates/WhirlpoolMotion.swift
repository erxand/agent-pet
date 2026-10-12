import CoreGraphics
import Foundation

package struct WhirlpoolMotion: Equatable {
    package static let durationInSeconds: Double = 0.8
    package static let turns: Double = 1.75
    package static let aimFollowRatePerSecond: Double = 6
    package static let smallestScale: Double = 0.05

    package let start: CGPoint
    package private(set) var target: CGPoint
    package private(set) var aim: CGPoint
    package private(set) var elapsedSeconds: Double = 0
    private let startOffset: CGVector
    private let turnDirection: Double

    package init(from start: CGPoint, toward target: CGPoint) {
        self.start = start
        self.target = target
        aim = target
        startOffset = CGVector(dx: start.x - target.x, dy: start.y - target.y)
        turnDirection = start.x <= target.x ? -1 : 1
    }

    package var progress: Double { min(max(elapsedSeconds / WhirlpoolMotion.durationInSeconds, 0), 1) }

    package var isFinished: Bool { elapsedSeconds >= WhirlpoolMotion.durationInSeconds }

    package var easedProgress: Double { progress * progress }

    package var center: CGPoint {
        let remaining = 1 - easedProgress
        let angle = turnDirection * WhirlpoolMotion.turns * 2 * Double.pi * easedProgress
        let rotated = CGVector(
            dx: startOffset.dx * CGFloat(cos(angle)) - startOffset.dy * CGFloat(sin(angle)),
            dy: startOffset.dx * CGFloat(sin(angle)) + startOffset.dy * CGFloat(cos(angle))
        )
        return CGPoint(x: aim.x + rotated.dx * CGFloat(remaining), y: aim.y + rotated.dy * CGFloat(remaining))
    }

    package var rotationInRadians: Double {
        turnDirection * WhirlpoolMotion.turns * 2 * Double.pi * easedProgress
    }

    package var scale: Double {
        max(WhirlpoolMotion.smallestScale, 1 - easedProgress)
    }

    package var opacity: Double {
        1 - easedProgress * easedProgress
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
