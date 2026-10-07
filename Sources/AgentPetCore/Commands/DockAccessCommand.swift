import ApplicationServices
import Foundation

package protocol DockAccessChecking {
    func isGranted() -> Bool
    func ask() -> Bool
}

package struct AccessibilityDockAccess: DockAccessChecking {
    package init() {}

    package func isGranted() -> Bool {
        AXIsProcessTrusted()
    }

    package func ask() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

enum DockAccessCommand {
    package static let grantedWord = "granted"
    package static let notGrantedWord = "not granted"
    package static let settingsHint = "System Settings > Privacy & Security > Accessibility"

    static func run(flags: ParsedFlags, access: DockAccessChecking = AccessibilityDockAccess()) -> Int32 {
        let granted = flags.isPresent(.ask) ? access.ask() : access.isGranted()
        print(granted ? grantedWord : notGrantedWord)
        guard !granted else { return ExitCode.success }
        if flags.isPresent(.ask) {
            CommandFeedback.writeToStandardError("turn on agent-pet in \(settingsHint), then restart the daemon.")
        }
        return ExitCode.failure
    }
}
