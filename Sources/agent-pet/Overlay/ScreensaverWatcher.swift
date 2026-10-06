import AgentPetCore
import AppKit
import CoreGraphics

final class ScreensaverWatcher {
    static let pollIntervalInSeconds: TimeInterval = 1

    private var bundleIdentifiers: Set<String> = []
    private var simulates = false
    private var matchingProcessIdentifiers: Set<Int32> = []
    private var lastPollAt: TimeInterval?
    private var lastCover: ScreensaverCover?
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshRunningApplications()
            }
        }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
    }

    func configure(bundleIdentifiers: [String], simulates: Bool) {
        let identifiers = Set(bundleIdentifiers)
        self.simulates = simulates
        guard identifiers != self.bundleIdentifiers else { return }
        self.bundleIdentifiers = identifiers
        refreshRunningApplications()
    }

    func currentCover(now: TimeInterval) -> ScreensaverCover? {
        if simulates { return ScreensaverCover(windowLevel: NSWindow.Level.screenSaver.rawValue) }
        guard !matchingProcessIdentifiers.isEmpty else {
            lastCover = nil
            return nil
        }
        if let lastPollAt, now - lastPollAt < ScreensaverWatcher.pollIntervalInSeconds { return lastCover }
        lastPollAt = now
        lastCover = ScreensaverDetection.cover(
            windows: ScreensaverWatcher.onScreenWindows(),
            ownerProcessIdentifiers: matchingProcessIdentifiers,
            displayBounds: ScreensaverWatcher.displayBounds()
        )
        return lastCover
    }

    private func refreshRunningApplications() {
        matchingProcessIdentifiers = Set(
            NSWorkspace.shared.runningApplications
                .filter { application in application.bundleIdentifier.map(bundleIdentifiers.contains) ?? false }
                .map { application in application.processIdentifier }
        )
        lastPollAt = nil
    }

    private static func onScreenWindows() -> [ScreensaverWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let descriptions = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return descriptions.compactMap { description in
            guard let owner = description[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDictionary = description[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else { return nil }
            return ScreensaverWindow(
                ownerProcessIdentifier: owner,
                bounds: bounds,
                level: description[kCGWindowLayer as String] as? Int ?? 0,
                alpha: description[kCGWindowAlpha as String] as? Double ?? 1,
                isOnScreen: description[kCGWindowIsOnscreen as String] as? Bool ?? true
            )
        }
    }

    private static func displayBounds() -> [CGRect] {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success else { return [] }
        return displays.prefix(Int(displayCount)).map { display in CGDisplayBounds(display) }
    }
}
