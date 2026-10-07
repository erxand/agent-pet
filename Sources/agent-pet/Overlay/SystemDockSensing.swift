import AgentPetCore
import AppKit
import ApplicationServices

final class SystemDockSensing: DockSensing {
    private static let dockBundleIdentifier = "com.apple.dock"
    private static let dockWindowLayer = 20
    private static let accessCheckIntervalInSeconds: TimeInterval = 5
    private static let messagingTimeoutInSeconds: Float = 0.05
    private static let tileDataKey = "tile-data"
    private static let bundleIdentifierKey = "bundle-identifier"
    private static let fixedTileCount = 2
    private static let shownRecentsLimit = 3

    private var dockApplication: AXUIElement?
    private var dockList: AXUIElement?
    private var dockProcessIdentifier: pid_t?
    private var accessGranted = false
    private var accessCheckedAt: TimeInterval?

    func preferences() -> DockPreferences {
        let domain = DockPreferences.domain as CFString
        CFPreferencesAppSynchronize(domain)
        let orientation = (value(DockPreferences.orientationKey, in: domain) as? String)
            .flatMap { rawValue in DockOrientation(rawValue: rawValue) } ?? .bottom
        let autohides = (value(DockPreferences.autohideKey, in: domain) as? Bool) ?? false
        let tileSize = (value(DockPreferences.tileSizeKey, in: domain) as? NSNumber).map { number in CGFloat(number.doubleValue) }
            ?? DockPreferences.defaultTileSize
        let showsRecents = (value(DockPreferences.showsRecentsKey, in: domain) as? Bool) ?? true
        let pinnedApps = (value(DockPreferences.persistentAppsKey, in: domain) as? [[String: Any]]) ?? []
        let others = (value(DockPreferences.persistentOthersKey, in: domain) as? [[String: Any]]) ?? []
        let recents = (value(DockPreferences.recentAppsKey, in: domain) as? [[String: Any]]) ?? []
        let pinnedIdentifiers = Set(pinnedApps.compactMap { tile in
            (tile[SystemDockSensing.tileDataKey] as? [String: Any])?[SystemDockSensing.bundleIdentifierKey] as? String
        })
        let runningUnpinned = NSWorkspace.shared.runningApplications.filter { application in
            application.activationPolicy == .regular
                && application.bundleIdentifier != SystemDockSensing.dockBundleIdentifier
                && !pinnedIdentifiers.contains(application.bundleIdentifier ?? "")
        }.count
        let middleSection = showsRecents ? max(runningUnpinned, min(recents.count, SystemDockSensing.shownRecentsLimit)) : runningUnpinned
        return DockPreferences(
            orientation: orientation,
            autohides: autohides,
            tileSize: tileSize,
            tileCount: SystemDockSensing.fixedTileCount + pinnedApps.count + middleSection + others.count,
            separatorCount: 1 + (middleSection > 0 ? 1 : 0)
        )
    }

    func accessibilityListFrame() -> CGRect? {
        guard isAccessGranted(), let list = currentDockList() else { return nil }
        guard let position = pointValue(of: list, attribute: kAXPositionAttribute),
              let size = sizeValue(of: list, attribute: kAXSizeAttribute)
        else {
            dockList = nil
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    func dockIsShownOnScreen() -> Bool? {
        guard let processIdentifier = currentDockProcessIdentifier() else { return nil }
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        return windows.contains { window in
            (window[kCGWindowOwnerPID as String] as? Int).map { owner in pid_t(owner) == processIdentifier } == true
                && (window[kCGWindowLayer as String] as? Int) == SystemDockSensing.dockWindowLayer
        }
    }

    func pointerLocation() -> CGPoint {
        NSEvent.mouseLocation
    }

    private func value(_ key: String, in domain: CFString) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, domain)
    }

    private func isAccessGranted() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if let accessCheckedAt, now - accessCheckedAt < SystemDockSensing.accessCheckIntervalInSeconds {
            return accessGranted
        }
        accessCheckedAt = now
        accessGranted = AXIsProcessTrusted()
        return accessGranted
    }

    private func currentDockProcessIdentifier() -> pid_t? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: SystemDockSensing.dockBundleIdentifier).first else {
            dockProcessIdentifier = nil
            return nil
        }
        if dock.processIdentifier != dockProcessIdentifier {
            dockProcessIdentifier = dock.processIdentifier
            dockApplication = nil
            dockList = nil
        }
        return dock.processIdentifier
    }

    private func currentDockList() -> AXUIElement? {
        guard let processIdentifier = currentDockProcessIdentifier() else { return nil }
        if let dockList { return dockList }
        let application = dockApplication ?? AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, SystemDockSensing.messagingTimeoutInSeconds)
        dockApplication = application
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXChildrenAttribute as CFString, &children) == .success,
              let elements = children as? [AXUIElement]
        else { return nil }
        dockList = elements.first { element in
            var role: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success else { return false }
            return (role as? String) == kAXListRole
        }
        return dockList
    }

    private func pointValue(of element: AXUIElement, attribute: String) -> CGPoint? {
        var point = CGPoint.zero
        guard let axValue = axValue(of: element, attribute: attribute), AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeValue(of element: AXUIElement, attribute: String) -> CGSize? {
        var size = CGSize.zero
        guard let axValue = axValue(of: element, attribute: attribute), AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    private func axValue(of element: AXUIElement, attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXValue.self)
    }
}

final class DockGround {
    private let sensing: DockSensing
    private var tracker = DockTracker()

    init(sensing: DockSensing = SystemDockSensing()) {
        self.sensing = sensing
    }

    private(set) var lastBar: CGRect?

    func bar(now: TimeInterval, elapsedSeconds: Double) -> CGRect? {
        let screens = NSScreen.screens.map { screen in screen.frame }
        guard let primaryFrame = screens.first else { return nil }
        lastBar = tracker.update(
            now: now,
            elapsedSeconds: elapsedSeconds,
            screens: DockScreens(primaryFrame: primaryFrame, dockScreenFrame: primaryFrame, allFrames: screens),
            sensing: sensing
        )
        return lastBar
    }
}
