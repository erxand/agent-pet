import AgentPetCore
import AppKit
import CoreGraphics

protocol AppWindowWatching: AnyObject {
    func watch(bundleIdentifiers wanted: Set<String>)
    func summaries(now: TimeInterval) -> [String: AppWindowSummary]
}

final class AppWindowWatcher: AppWindowWatching {
    static let pollIntervalInSeconds: TimeInterval = 1

    private var bundleIdentifiers: Set<String> = []
    private var processIdentifiersByBundleIdentifier: [String: Set<Int32>] = [:]
    private var lastPollAt: TimeInterval?
    private var lastSummaries: [String: AppWindowSummary] = [:]
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

    func watch(bundleIdentifiers wanted: Set<String>) {
        guard wanted != bundleIdentifiers else { return }
        bundleIdentifiers = wanted
        refreshRunningApplications()
    }

    func summaries(now: TimeInterval) -> [String: AppWindowSummary] {
        guard !processIdentifiersByBundleIdentifier.isEmpty else {
            lastSummaries = [:]
            return [:]
        }
        if let lastPollAt, now - lastPollAt < AppWindowWatcher.pollIntervalInSeconds { return lastSummaries }
        lastPollAt = now
        lastSummaries = WindowDetection.summaries(
            windows: AppWindowWatcher.onScreenWindows(),
            processIdentifiersByBundleIdentifier: processIdentifiersByBundleIdentifier,
            displayBounds: AppWindowWatcher.displayBounds()
        )
        return lastSummaries
    }

    private func refreshRunningApplications() {
        var running: [String: Set<Int32>] = [:]
        for application in NSWorkspace.shared.runningApplications {
            guard let bundleIdentifier = application.bundleIdentifier, bundleIdentifiers.contains(bundleIdentifier) else { continue }
            running[bundleIdentifier, default: []].insert(application.processIdentifier)
        }
        processIdentifiersByBundleIdentifier = running
        lastPollAt = nil
    }

    private static func onScreenWindows() -> [AppWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let descriptions = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return descriptions.compactMap { description in
            guard let owner = description[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDictionary = description[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else { return nil }
            return AppWindow(
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
