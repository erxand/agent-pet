import CoreGraphics
import Foundation

package struct ScreensaverWindow: Equatable {
    package let ownerProcessIdentifier: Int32
    package let bounds: CGRect
    package let level: Int
    package let alpha: Double
    package let isOnScreen: Bool

    package init(ownerProcessIdentifier: Int32, bounds: CGRect, level: Int, alpha: Double, isOnScreen: Bool) {
        self.ownerProcessIdentifier = ownerProcessIdentifier
        self.bounds = bounds
        self.level = level
        self.alpha = alpha
        self.isOnScreen = isOnScreen
    }
}

package struct ScreensaverCover: Equatable {
    package let windowLevel: Int

    package init(windowLevel: Int) {
        self.windowLevel = windowLevel
    }
}

package enum ScreensaverResponse: Equatable {
    case none
    case hidePets
    case floatPets(levelAbove: Int)
}

package enum ScreensaverDetection {
    package static let minimumCoveredFraction: CGFloat = 0.9

    package static func cover(
        windows: [ScreensaverWindow],
        ownerProcessIdentifiers: Set<Int32>,
        displayBounds: [CGRect]
    ) -> ScreensaverCover? {
        let coveringLevels = windows
            .filter { window in
                ownerProcessIdentifiers.contains(window.ownerProcessIdentifier)
                    && window.isOnScreen
                    && window.alpha > 0
                    && displayBounds.contains { display in covers(window.bounds, display: display) }
            }
            .map { window in window.level }
        guard let highestLevel = coveringLevels.max() else { return nil }
        return ScreensaverCover(windowLevel: highestLevel)
    }

    package static func response(to cover: ScreensaverCover?, floatsOverScreensaver: Bool) -> ScreensaverResponse {
        guard let cover else { return .none }
        return floatsOverScreensaver ? .floatPets(levelAbove: cover.windowLevel) : .hidePets
    }

    package static func floatingPetLevel(screensaverLevel: Int, petLevel: Int, shieldingLevel: Int) -> Int {
        min(max(screensaverLevel + 1, petLevel), shieldingLevel - 1)
    }

    private static func covers(_ windowBounds: CGRect, display: CGRect) -> Bool {
        let displayArea = display.width * display.height
        guard displayArea > 0 else { return false }
        let overlap = windowBounds.intersection(display)
        guard !overlap.isNull else { return false }
        return overlap.width * overlap.height >= displayArea * minimumCoveredFraction
    }
}
