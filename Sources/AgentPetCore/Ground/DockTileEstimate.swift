import CoreGraphics
import Foundation

package enum DockTileEstimate {
    package static func minimizedTileCenter(
        preferences: DockPreferences,
        screenFrame: CGRect,
        listFrame: CGRect?
    ) -> CGPoint {
        let tileSize = preferences.tileSize
        let thickness = tileSize + DockListFrame.verticalPadding
        let estimatedLength = DockListFrame.estimated(preferences: preferences, screenFrame: screenFrame, shownFraction: 1).width
        let inFromTrailingEnd = DockListFrame.endPadding + DockListFrame.tileSpacing + tileSize * 1.5
        let sitsWhereShown = listFrame == nil || preferences.autohides
        switch preferences.orientation {
        case .bottom:
            let span = listFrame.map { frame in frame.minX...frame.maxX }
                ?? (screenFrame.midX - estimatedLength / 2)...(screenFrame.midX + estimatedLength / 2)
            let shownY = screenFrame.minY + DockListFrame.shownBottomGap + thickness / 2
            let y = sitsWhereShown ? shownY : listFrame?.midY ?? shownY
            return CGPoint(x: max(span.lowerBound, span.upperBound - inFromTrailingEnd), y: y)
        case .left, .right:
            let span = listFrame.map { frame in frame.minY...frame.maxY }
                ?? (screenFrame.midY - estimatedLength / 2)...(screenFrame.midY + estimatedLength / 2)
            let shownX = preferences.orientation == .left
                ? screenFrame.minX + DockListFrame.shownBottomGap + thickness / 2
                : screenFrame.maxX - DockListFrame.shownBottomGap - thickness / 2
            let x = sitsWhereShown ? shownX : listFrame?.midX ?? shownX
            return CGPoint(x: x, y: min(span.upperBound, span.lowerBound + inFromTrailingEnd))
        }
    }
}
