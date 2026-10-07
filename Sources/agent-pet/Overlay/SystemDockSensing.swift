import AgentPetCore
import AppKit
import ApplicationServices

final class SystemDockSensing: DockSensing {
    private static let dockBundleIdentifier = "com.apple.dock"
    private static let dockWindowLayer = 20
    private static let windowSearchIntervalInSeconds: TimeInterval = 2
    private static let messagingTimeoutInSeconds: Float = 0.05
    private static let tileDataKey = "tile-data"
    private static let bundleIdentifierKey = "bundle-identifier"
    private static let fixedTileCount = 2
    private static let shownRecentsLimit = 3

    private let accessGranted: () -> Bool
    private var dockProcessIdentifier: pid_t?
    private var dockApplication: AXUIElement?
    private var dockList: AXUIElement?
    private var dockWindowIdentifiers: [CGWindowID] = []
    private var windowSearchedAt: TimeInterval?
    private var observers: [NSObjectProtocol] = []

    init(accessGranted: @escaping () -> Bool) {
        self.accessGranted = accessGranted
        dockProcessIdentifier = SystemDockSensing.runningDock()?.processIdentifier
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                self?.dockChanged(notification, launched: true)
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                self?.dockChanged(notification, launched: false)
            }
        ]
    }

    deinit {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func preferences() -> DockPreferences {
        let domain = DockPreferences.domain as CFString
        CFPreferencesAppSynchronize(domain)
        let orientation = (value(DockPreferences.orientationKey, in: domain) as? String)
            .flatMap { rawValue in DockOrientation(rawValue: rawValue) } ?? .bottom
        let autohides = (value(DockPreferences.autohideKey, in: domain) as? Bool) ?? false
        let magnifies = (value(DockPreferences.magnificationKey, in: domain) as? Bool) ?? false
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
            magnifies: magnifies,
            tileCount: SystemDockSensing.fixedTileCount + pinnedApps.count + middleSection + others.count,
            separatorCount: 1 + (middleSection > 0 ? 1 : 0)
        )
    }

    func dockIsRunning() -> Bool {
        dockProcessIdentifier != nil
    }

    func accessibilityListFrame() -> CGRect? {
        guard accessGranted(), let list = currentDockList() else { return nil }
        guard let position = pointValue(of: list, attribute: kAXPositionAttribute),
              let size = sizeValue(of: list, attribute: kAXSizeAttribute)
        else {
            dockList = nil
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    func dockWindow() -> DockWindowState? {
        guard dockProcessIdentifier != nil else { return nil }
        if dockWindowIdentifiers.isEmpty { searchDockWindows() }
        let descriptions = describe(dockWindowIdentifiers)
        guard !descriptions.isEmpty else {
            dockWindowIdentifiers = []
            return nil
        }
        let frames = descriptions.map { description in
            (onScreen: (description[kCGWindowIsOnscreen as String] as? Bool) ?? false, frame: bounds(of: description))
        }
        let shown = frames.first { window in window.onScreen }
        return DockWindowState(isOnScreen: shown != nil, topLeftFrame: shown?.frame ?? frames.first?.frame)
    }

    func pointerLocation() -> CGPoint {
        NSEvent.mouseLocation
    }

    private static func runningDock() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleIdentifier).first
    }

    private func dockChanged(_ notification: Notification, launched: Bool) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              application.bundleIdentifier == SystemDockSensing.dockBundleIdentifier
        else { return }
        dockProcessIdentifier = launched ? application.processIdentifier : nil
        dockApplication = nil
        dockList = nil
        dockWindowIdentifiers = []
        windowSearchedAt = nil
    }

    private func searchDockWindows() {
        let now = ProcessInfo.processInfo.systemUptime
        if let windowSearchedAt, now - windowSearchedAt < SystemDockSensing.windowSearchIntervalInSeconds { return }
        windowSearchedAt = now
        guard let processIdentifier = dockProcessIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
        else { return }
        dockWindowIdentifiers = windows.compactMap { window in
            guard (window[kCGWindowOwnerPID as String] as? Int).map({ owner in pid_t(owner) == processIdentifier }) == true,
                  (window[kCGWindowLayer as String] as? Int) == SystemDockSensing.dockWindowLayer,
                  let number = window[kCGWindowNumber as String] as? Int
            else { return nil }
            return CGWindowID(number)
        }
    }

    private func describe(_ identifiers: [CGWindowID]) -> [[String: Any]] {
        guard !identifiers.isEmpty else { return [] }
        var pointers: [UnsafeRawPointer?] = identifiers.map { identifier in UnsafeRawPointer(bitPattern: UInt(identifier)) }
        guard let array = CFArrayCreate(nil, &pointers, pointers.count, nil),
              let descriptions = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]]
        else { return [] }
        return descriptions
    }

    private func bounds(of description: [String: Any]) -> CGRect? {
        guard let dictionary = description[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dictionary)
    }

    private func value(_ key: String, in domain: CFString) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, domain)
    }

    private func currentDockList() -> AXUIElement? {
        guard let processIdentifier = dockProcessIdentifier else { return nil }
        if let dockList { return dockList }
        let application = dockApplication ?? AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, SystemDockSensing.messagingTimeoutInSeconds)
        dockApplication = application
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXChildrenAttribute as CFString, &children) == .success,
              let elements = children as? [AXUIElement]
        else { return nil }
        let list = elements.first { element in
            var role: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success else { return false }
            return (role as? String) == kAXListRole
        }
        if let list { AXUIElementSetMessagingTimeout(list, SystemDockSensing.messagingTimeoutInSeconds) }
        dockList = list
        return list
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
    private let screenFrames: () -> [CGRect]
    private var tracker = DockTracker()

    init(sensing: DockSensing, screenFrames: @escaping () -> [CGRect] = { NSScreen.screens.map { screen in screen.frame } }) {
        self.sensing = sensing
        self.screenFrames = screenFrames
    }

    private(set) var lastBar: CGRect?

    func bar(now: TimeInterval, elapsedSeconds: Double) -> CGRect? {
        let frames = screenFrames()
        guard let primaryFrame = frames.first else { return nil }
        lastBar = tracker.update(
            now: now,
            elapsedSeconds: elapsedSeconds,
            screens: DockScreens(primaryFrame: primaryFrame, allFrames: frames),
            sensing: sensing
        )
        return lastBar
    }
}
