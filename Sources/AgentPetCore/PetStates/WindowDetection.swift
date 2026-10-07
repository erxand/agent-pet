import CoreGraphics
import Foundation

package struct AppWindow: Equatable {
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

package struct AppWindowSummary: Equatable {
    package let coversDisplay: Bool
    package let topLevel: Int

    package init(coversDisplay: Bool, topLevel: Int) {
        self.coversDisplay = coversDisplay
        self.topLevel = topLevel
    }
}

package enum WindowDetection {
    package static let minimumCoveredFraction: CGFloat = 0.9

    package static func summaries(
        windows: [AppWindow],
        processIdentifiersByBundleIdentifier: [String: Set<Int32>],
        displayBounds: [CGRect]
    ) -> [String: AppWindowSummary] {
        var summaries: [String: AppWindowSummary] = [:]
        for (bundleIdentifier, processIdentifiers) in processIdentifiersByBundleIdentifier {
            let shown = windows.filter { window in
                processIdentifiers.contains(window.ownerProcessIdentifier) && window.isOnScreen && window.alpha > 0
            }
            guard let topLevel = shown.map({ window in window.level }).max() else { continue }
            let coversDisplay = shown.contains { window in
                displayBounds.contains { display in covers(window.bounds, display: display) }
            }
            summaries[bundleIdentifier] = AppWindowSummary(coversDisplay: coversDisplay, topLevel: topLevel)
        }
        return summaries
    }

    package static func windowLevel(
        for level: PetLevel,
        summaries: [String: AppWindowSummary],
        petLevel: Int,
        shieldingLevel: Int
    ) -> Int {
        switch level {
        case .normal:
            return petLevel
        case .above(let bundleIdentifier):
            guard let topLevel = summaries[bundleIdentifier]?.topLevel else { return petLevel }
            return min(max(topLevel + 1, petLevel), shieldingLevel - 1)
        }
    }

    private static func covers(_ windowBounds: CGRect, display: CGRect) -> Bool {
        let displayArea = display.width * display.height
        guard displayArea > 0 else { return false }
        let overlap = windowBounds.intersection(display)
        guard !overlap.isNull else { return false }
        return overlap.width * overlap.height >= displayArea * minimumCoveredFraction
    }
}
