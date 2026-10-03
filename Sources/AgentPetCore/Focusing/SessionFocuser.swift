import AppKit

package enum TerminalBundleIdentifier: String, CaseIterable {
    case iterm2 = "com.googlecode.iterm2"
    case appleTerminal = "com.apple.Terminal"
    case ghostty = "com.mitchellh.ghostty"
}

package struct TmuxClient {
    package let terminalDevicePath: String
    package let sessionName: String
    package let activity: Double
}

package enum TmuxClientListing {
    package static let format = "#{client_tty}\t#{session_name}\t#{client_activity}"

    private static let fieldSeparator: Character = "\t"
    private static let rowSeparator: Character = "\n"
    private static let terminalDevicePathFieldIndex = 0
    private static let sessionNameFieldIndex = 1
    private static let activityFieldIndex = 2
    private static let fieldCount = 3

    package static func parse(_ output: String) -> [TmuxClient] {
        output.split(separator: rowSeparator).compactMap { row in
            let fields = row.split(separator: fieldSeparator, omittingEmptySubsequences: false)
            guard fields.count == fieldCount else { return nil }
            let terminalDevicePath = String(fields[terminalDevicePathFieldIndex])
            let sessionName = String(fields[sessionNameFieldIndex])
            guard !terminalDevicePath.isEmpty, !sessionName.isEmpty else { return nil }
            guard let activity = Double(fields[activityFieldIndex]) else { return nil }
            return TmuxClient(
                terminalDevicePath: terminalDevicePath,
                sessionName: sessionName,
                activity: activity
            )
        }
    }

    package static func preferredClient(in clients: [TmuxClient], attachedTo sessionName: String) -> TmuxClient? {
        let alreadyAttached = clients.first { client in client.sessionName == sessionName }
        if let alreadyAttached { return alreadyAttached }
        return clients.max { leftClient, rightClient in leftClient.activity < rightClient.activity }
    }
}

package enum SessionFocuser {
    package static let clientSwitchEnabledByDefault = true

    private static let osascriptExecutablePath = "/usr/bin/osascript"
    private static let osascriptExpressionFlag = "-e"
    private static let itermApplicationName = "iTerm2"
    private static let itermFocusSuccessMarker = "focused"
    private static let doubleQuote = "\""
    private static let escapedDoubleQuote = "\\\""

    package static func focus(tmuxTarget: TmuxTarget?, allowsClientSwitch: Bool = clientSwitchEnabledByDefault) {
        let chosenClient = tmuxTarget.flatMap { target in
            selectTmuxPane(target, allowsClientSwitch: allowsClientSwitch)
        }
        if allowsClientSwitch,
           let chosenClient,
           focusItermSession(terminalDevicePath: chosenClient.terminalDevicePath) {
            return
        }
        activateFirstRunningTerminal()
    }

    private static func selectTmuxPane(_ target: TmuxTarget, allowsClientSwitch: Bool) -> TmuxClient? {
        TmuxCommandRunner.run(
            subcommand: .selectWindow,
            arguments: [TmuxCommandRunner.targetFlag, target.windowTarget]
        )
        TmuxCommandRunner.run(
            subcommand: .selectPane,
            arguments: [TmuxCommandRunner.targetFlag, target.paneIdentifier]
        )
        guard let chosenClient = chooseClient(forSessionNamed: target.sessionName) else { return nil }
        guard allowsClientSwitch, chosenClient.sessionName != target.sessionName else { return chosenClient }
        TmuxCommandRunner.run(
            subcommand: .switchClient,
            arguments: [
                TmuxCommandRunner.clientFlag,
                chosenClient.terminalDevicePath,
                TmuxCommandRunner.targetFlag,
                target.sessionName
            ]
        )
        return chosenClient
    }

    private static func chooseClient(forSessionNamed sessionName: String) -> TmuxClient? {
        let listing = TmuxCommandRunner.capture(
            subcommand: .listClients,
            arguments: [TmuxCommandRunner.formatFlag, TmuxClientListing.format]
        )
        guard let listing else { return nil }
        return TmuxClientListing.preferredClient(in: TmuxClientListing.parse(listing), attachedTo: sessionName)
    }

    private static func focusItermSession(terminalDevicePath: String) -> Bool {
        guard isRunning(bundleIdentifier: .iterm2) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: osascriptExecutablePath)
        process.arguments = [osascriptExpressionFlag, itermFocusScript(terminalDevicePath: terminalDevicePath)]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        do {
            try process.run()
        } catch {
            return false
        }
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == ExitCode.success else { return false }
        let output = String(decoding: outputData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output == itermFocusSuccessMarker
    }

    private static func itermFocusScript(terminalDevicePath: String) -> String {
        let escapedDevicePath = terminalDevicePath.replacingOccurrences(
            of: doubleQuote,
            with: escapedDoubleQuote
        )
        return """
        tell application "\(itermApplicationName)"
            repeat with terminalWindow in windows
                repeat with terminalTab in tabs of terminalWindow
                    repeat with terminalSession in sessions of terminalTab
                        if tty of terminalSession is "\(escapedDevicePath)" then
                            select terminalTab
                            select terminalSession
                            set index of terminalWindow to 1
                            activate
                            return "\(itermFocusSuccessMarker)"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
    }

    private static func isRunning(bundleIdentifier: TerminalBundleIdentifier) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier.rawValue).isEmpty
    }

    private static func activateFirstRunningTerminal() {
        for bundleIdentifier in TerminalBundleIdentifier.allCases {
            guard isRunning(bundleIdentifier: bundleIdentifier) else { continue }
            guard let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier.rawValue
            ) else { continue }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
            return
        }
    }
}
