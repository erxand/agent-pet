import AgentPetCore
import AppKit

enum DockTileSource: Equatable {
    case minimizedTile
    case applicationTile
    case estimate
}

struct DockTileLocation: Equatable {
    let center: CGPoint
    let source: DockTileSource
    let isFinal: Bool
}

final class DockTileLocator {
    static let tileSearchSeconds: TimeInterval = 1.5

    private let system: DockSystem
    private let accessGranted: () -> Bool
    private let primaryScreenFrame: () -> CGRect

    init(
        system: DockSystem,
        accessGranted: @escaping () -> Bool,
        primaryScreenFrame: @escaping () -> CGRect = { NSScreen.screens.first?.frame ?? .zero }
    ) {
        self.system = system
        self.accessGranted = accessGranted
        self.primaryScreenFrame = primaryScreenFrame
    }

    func locate(windowTitle: String, applicationName: String?, searchedForSeconds: TimeInterval) -> DockTileLocation {
        let preferences = system.preferences()
        let screenFrame = primaryScreenFrame()
        let dockProcessIdentifier = accessGranted() ? system.lookUpDockProcessIdentifier() : nil
        let items = dockProcessIdentifier.map { processIdentifier in system.accessibilityDockItems(processIdentifier: processIdentifier) } ?? []
        if preferences.minimizesToApplication {
            if let applicationName, let tile = center(of: items, subrole: DockItemDescription.applicationSubrole, title: applicationName, screenFrame: screenFrame) {
                return DockTileLocation(center: tile, source: .applicationTile, isFinal: true)
            }
        } else if let tile = center(of: items, subrole: DockItemDescription.minimizedWindowSubrole, title: windowTitle, screenFrame: screenFrame) {
            return DockTileLocation(center: tile, source: .minimizedTile, isFinal: true)
        }
        let listFrame = dockProcessIdentifier
            .flatMap { processIdentifier in system.accessibilityListFrame(processIdentifier: processIdentifier) }
            .map { topLeftFrame in DockListFrame.appKitFrame(fromTopLeftFrame: topLeftFrame, primaryScreenHeight: screenFrame.maxY) }
        let estimate = DockTileEstimate.minimizedTileCenter(preferences: preferences, screenFrame: screenFrame, listFrame: listFrame)
        let stillSearching = dockProcessIdentifier != nil
            && !preferences.minimizesToApplication
            && searchedForSeconds < DockTileLocator.tileSearchSeconds
        return DockTileLocation(center: estimate, source: .estimate, isFinal: !stillSearching)
    }

    static func comparableTitle(_ title: String) -> String {
        let trimmed = title.drop { character in !(character.isLetter || character.isNumber) }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func center(of items: [DockItemDescription], subrole: String, title: String, screenFrame: CGRect) -> CGPoint? {
        let wanted = DockTileLocator.comparableTitle(title)
        guard !wanted.isEmpty else { return nil }
        let match = items.first { item in
            item.subrole == subrole && item.title.map(DockTileLocator.comparableTitle) == wanted && item.topLeftFrame != nil
        }
        guard let topLeftFrame = match?.topLeftFrame else { return nil }
        let frame = DockListFrame.appKitFrame(fromTopLeftFrame: topLeftFrame, primaryScreenHeight: screenFrame.maxY)
        return CGPoint(x: frame.midX, y: frame.midY)
    }
}
