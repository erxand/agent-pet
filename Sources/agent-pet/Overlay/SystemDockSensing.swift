import AgentPetCore
import AppKit
import ApplicationServices

struct DockWindowDescription: Equatable {
    let isOnScreen: Bool
    let topLeftFrame: CGRect?
}

protocol DockSystem: AnyObject {
    var processChanges: Int { get }
    func uptime() -> TimeInterval
    func lookUpDockProcessIdentifier() -> pid_t?
    func isRunning(_ processIdentifier: pid_t) -> Bool
    func dockWindowIdentifiers(ownedBy processIdentifier: pid_t) -> [CGWindowID]
    func describeWindows(_ identifiers: [CGWindowID]) -> [DockWindowDescription]
    func accessibilityListFrame(processIdentifier: pid_t) -> CGRect?
    func preferences() -> DockPreferences
    func pointerLocation() -> CGPoint
}

final class SystemDockSensing: DockSensing {
    static let validationIntervalInSeconds: TimeInterval = 0.5
    static let lookupIntervalInSeconds: TimeInterval = 1
    static let windowSearchIntervalInSeconds: TimeInterval = 2

    private let system: DockSystem
    private let accessGranted: () -> Bool
    private var dockProcessIdentifier: pid_t?
    private var seenProcessChanges: Int?
    private var lookedUpAt: TimeInterval?
    private var validatedAt: TimeInterval?
    private var dockWindowIdentifiers: [CGWindowID] = []
    private var windowSearchedAt: TimeInterval?

    init(system: DockSystem = LiveDockSystem(), accessGranted: @escaping () -> Bool) {
        self.system = system
        self.accessGranted = accessGranted
    }

    func preferences() -> DockPreferences {
        system.preferences()
    }

    func dockIsRunning() -> Bool {
        currentDockProcessIdentifier() != nil
    }

    func accessibilityListFrame() -> CGRect? {
        guard accessGranted(), let processIdentifier = currentDockProcessIdentifier() else { return nil }
        return system.accessibilityListFrame(processIdentifier: processIdentifier)
    }

    func dockWindow() -> DockWindowState? {
        guard let processIdentifier = currentDockProcessIdentifier() else { return nil }
        if dockWindowIdentifiers.isEmpty { searchDockWindows(ownedBy: processIdentifier, force: false) }
        var descriptions = system.describeWindows(dockWindowIdentifiers)
        if descriptions.isEmpty && !dockWindowIdentifiers.isEmpty {
            searchDockWindows(ownedBy: processIdentifier, force: true)
            descriptions = system.describeWindows(dockWindowIdentifiers)
        }
        guard !descriptions.isEmpty else { return nil }
        let shown = descriptions.first { window in window.isOnScreen }
        return DockWindowState(isOnScreen: shown != nil, topLeftFrame: shown?.topLeftFrame ?? descriptions.first?.topLeftFrame)
    }

    func pointerLocation() -> CGPoint {
        system.pointerLocation()
    }

    private func currentDockProcessIdentifier() -> pid_t? {
        let now = system.uptime()
        let changed = system.processChanges != seenProcessChanges
        seenProcessChanges = system.processChanges
        if !changed, let cached = dockProcessIdentifier {
            if let validatedAt, now - validatedAt < SystemDockSensing.validationIntervalInSeconds { return cached }
            validatedAt = now
            if system.isRunning(cached) { return cached }
        }
        if !changed, dockProcessIdentifier == nil, let lookedUpAt, now - lookedUpAt < SystemDockSensing.lookupIntervalInSeconds {
            return nil
        }
        lookedUpAt = now
        validatedAt = now
        let found = system.lookUpDockProcessIdentifier()
        if found != dockProcessIdentifier {
            dockWindowIdentifiers = []
            windowSearchedAt = nil
        }
        dockProcessIdentifier = found
        return found
    }

    private func searchDockWindows(ownedBy processIdentifier: pid_t, force: Bool) {
        let now = system.uptime()
        if !force, let windowSearchedAt, now - windowSearchedAt < SystemDockSensing.windowSearchIntervalInSeconds { return }
        windowSearchedAt = now
        dockWindowIdentifiers = system.dockWindowIdentifiers(ownedBy: processIdentifier)
    }
}

final class LiveDockSystem: DockSystem {
    private static let dockBundleIdentifier = "com.apple.dock"
    private static let dockWindowLayer = 20
    private static let messagingTimeoutInSeconds: Float = 0.05
    private static let tileDataKey = "tile-data"
    private static let bundleIdentifierKey = "bundle-identifier"
    private static let fixedTileCount = 2
    private static let shownRecentsLimit = 3

    private(set) var processChanges = 0
    private var runningApplicationsObservation: NSKeyValueObservation?
    private var elementsProcessIdentifier: pid_t?
    private var dockApplication: AXUIElement?
    private var dockList: AXUIElement?

    init() {
        runningApplicationsObservation = NSWorkspace.shared.observe(\.runningApplications, options: []) { [weak self] _, _ in
            self?.processChanges += 1
        }
    }

    func uptime() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    func lookUpDockProcessIdentifier() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: LiveDockSystem.dockBundleIdentifier)
            .first { application in !application.isTerminated }?
            .processIdentifier
    }

    func isRunning(_ processIdentifier: pid_t) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: processIdentifier) else { return false }
        return !application.isTerminated && application.bundleIdentifier == LiveDockSystem.dockBundleIdentifier
    }

    func dockWindowIdentifiers(ownedBy processIdentifier: pid_t) -> [CGWindowID] {
        guard let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return windows.compactMap { window in
            guard (window[kCGWindowOwnerPID as String] as? Int).map({ owner in pid_t(owner) == processIdentifier }) == true,
                  (window[kCGWindowLayer as String] as? Int) == LiveDockSystem.dockWindowLayer,
                  let number = window[kCGWindowNumber as String] as? Int
            else { return nil }
            return CGWindowID(number)
        }
    }

    func describeWindows(_ identifiers: [CGWindowID]) -> [DockWindowDescription] {
        guard !identifiers.isEmpty else { return [] }
        var pointers: [UnsafeRawPointer?] = identifiers.map { identifier in UnsafeRawPointer(bitPattern: UInt(identifier)) }
        guard let array = CFArrayCreate(nil, &pointers, pointers.count, nil),
              let descriptions = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]]
        else { return [] }
        return descriptions.map { description in
            DockWindowDescription(
                isOnScreen: (description[kCGWindowIsOnscreen as String] as? Bool) ?? false,
                topLeftFrame: (description[kCGWindowBounds as String] as? NSDictionary).flatMap { bounds in
                    CGRect(dictionaryRepresentation: bounds)
                }
            )
        }
    }

    func accessibilityListFrame(processIdentifier: pid_t) -> CGRect? {
        guard let list = dockList(processIdentifier: processIdentifier) else { return nil }
        guard let position = pointValue(of: list, attribute: kAXPositionAttribute),
              let size = sizeValue(of: list, attribute: kAXSizeAttribute)
        else {
            dockList = nil
            return nil
        }
        return CGRect(origin: position, size: size)
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
            (tile[LiveDockSystem.tileDataKey] as? [String: Any])?[LiveDockSystem.bundleIdentifierKey] as? String
        })
        let runningUnpinned = NSWorkspace.shared.runningApplications.filter { application in
            application.activationPolicy == .regular
                && application.bundleIdentifier != LiveDockSystem.dockBundleIdentifier
                && !pinnedIdentifiers.contains(application.bundleIdentifier ?? "")
        }.count
        let middleSection = showsRecents ? max(runningUnpinned, min(recents.count, LiveDockSystem.shownRecentsLimit)) : runningUnpinned
        return DockPreferences(
            orientation: orientation,
            autohides: autohides,
            tileSize: tileSize,
            magnifies: magnifies,
            tileCount: LiveDockSystem.fixedTileCount + pinnedApps.count + middleSection + others.count,
            separatorCount: 1 + (middleSection > 0 ? 1 : 0)
        )
    }

    func pointerLocation() -> CGPoint {
        NSEvent.mouseLocation
    }

    private func value(_ key: String, in domain: CFString) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, domain)
    }

    private func dockList(processIdentifier: pid_t) -> AXUIElement? {
        if processIdentifier != elementsProcessIdentifier {
            elementsProcessIdentifier = processIdentifier
            dockApplication = nil
            dockList = nil
        }
        if let dockList { return dockList }
        let application = dockApplication ?? AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, LiveDockSystem.messagingTimeoutInSeconds)
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
        if let list { AXUIElementSetMessagingTimeout(list, LiveDockSystem.messagingTimeoutInSeconds) }
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

    var lastRestingTop: CGFloat? { tracker.restingTop }

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
