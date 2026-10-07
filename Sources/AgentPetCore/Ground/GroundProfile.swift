import CoreGraphics

package struct GroundSegment: Equatable {
    package let minX: CGFloat
    package let maxX: CGFloat
    package let top: CGFloat
    package let restingTop: CGFloat

    package init(minX: CGFloat, maxX: CGFloat, top: CGFloat, restingTop: CGFloat? = nil) {
        self.minX = minX
        self.maxX = maxX
        self.top = top
        self.restingTop = max(top, restingTop ?? top)
    }

    package func overlaps(_ span: ClosedRange<CGFloat>) -> Bool {
        span.upperBound > minX && span.lowerBound < maxX
    }
}

package enum GroundKind: Equatable {
    case flat
    case dock
}

package struct GroundProfile: Equatable {
    package let kind: GroundKind
    package let base: CGFloat
    package let segment: GroundSegment?

    package static func flat(base: CGFloat) -> GroundProfile {
        GroundProfile(kind: .flat, base: base, segment: nil)
    }

    package static func dock(base: CGFloat, segment: GroundSegment) -> GroundProfile {
        GroundProfile(kind: .dock, base: base, segment: segment)
    }

    package static func resolve(
        standsOnDock: Bool,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        dockBar: CGRect?,
        dockRestingTop: CGFloat? = nil,
        bottomInset: CGFloat
    ) -> GroundProfile {
        let today = flat(base: visibleFrame.minY + bottomInset)
        guard standsOnDock, let dockBar, isAtTheBottom(of: screenFrame, dockBar: dockBar) else { return today }
        return dock(
            base: screenFrame.minY + bottomInset,
            segment: GroundSegment(
                minX: dockBar.minX,
                maxX: dockBar.maxX,
                top: dockBar.maxY + bottomInset,
                restingTop: dockRestingTop.map { restingTop in restingTop + bottomInset }
            )
        )
    }

    package static func bodySpan(centerX: CGFloat, spriteSideLength: CGFloat, bodyWidthFraction: CGFloat) -> ClosedRange<CGFloat> {
        let halfBody = spriteSideLength * bodyWidthFraction / 2
        return (centerX - halfBody)...(centerX + halfBody)
    }

    package func height(over span: ClosedRange<CGFloat>) -> CGFloat {
        guard let segment, segment.overlaps(span) else { return base }
        return max(base, segment.top)
    }

    package func restingHeight(over span: ClosedRange<CGFloat>) -> CGFloat {
        guard let segment, segment.overlaps(span) else { return base }
        return max(base, segment.restingTop)
    }

    private static func isAtTheBottom(of screenFrame: CGRect, dockBar: CGRect) -> Bool {
        guard dockBar.width > 0, dockBar.height > 0 else { return false }
        guard dockBar.midX >= screenFrame.minX, dockBar.midX <= screenFrame.maxX else { return false }
        let reach = dockBar.height * 2
        return dockBar.minY <= screenFrame.minY + reach && dockBar.maxY >= screenFrame.minY - reach
    }
}
