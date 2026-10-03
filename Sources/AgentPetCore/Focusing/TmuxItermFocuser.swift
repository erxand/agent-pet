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

package protocol TerminalControlling {
    func isRunning(_ terminal: TerminalBundleIdentifier) -> Bool
    func runItermScript(_ script: String) -> String?
    func activate(_ terminal: TerminalBundleIdentifier) -> Bool
}

package struct SystemTerminalControl: TerminalControlling {
    private static let osascriptExecutablePath = "/usr/bin/osascript"
    private static let osascriptExpressionFlag = "-e"

    package init() {}

    package func isRunning(_ terminal: TerminalBundleIdentifier) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: terminal.rawValue).isEmpty
    }

    package func runItermScript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: SystemTerminalControl.osascriptExecutablePath)
        process.arguments = [SystemTerminalControl.osascriptExpressionFlag, script]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == ExitCode.success else { return nil }
        return String(decoding: outputData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    package func activate(_ terminal: TerminalBundleIdentifier) -> Bool {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: terminal.rawValue
        ) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
        return true
    }
}

package struct TmuxItermFocuser: Focuser {
    package static let clientSwitchEnabledByDefault = true

    private static let itermApplicationName = "iTerm2"
    private static let itermFocusSuccessMarker = "focused"
    private static let doubleQuote = "\""
    private static let escapedDoubleQuote = "\\\""

    private let tmux: TmuxCommandRunning
    private let terminals: TerminalControlling

    package init(
        tmux: TmuxCommandRunning = SystemTmux(),
        terminals: TerminalControlling = SystemTerminalControl()
    ) {
        self.tmux = tmux
        self.terminals = terminals
    }

    package func unavailability(for request: FocusRequest) -> FocusUnavailability? {
        request.tmuxTarget == nil ? .missingTmuxTarget : nil
    }

    package func focus(_ request: FocusRequest) {
        let chosenClient = request.tmuxTarget.flatMap { target in
            selectTmuxPane(target, allowsClientSwitch: request.allowsClientSwitch)
        }
        if request.allowsClientSwitch,
           let chosenClient,
           focusItermSession(terminalDevicePath: chosenClient.terminalDevicePath) {
            return
        }
        activateFirstRunningTerminal()
    }

    private func selectTmuxPane(_ target: TmuxTarget, allowsClientSwitch: Bool) -> TmuxClient? {
        tmux.run(
            subcommand: .selectWindow,
            arguments: [TmuxCommandRunner.targetFlag, target.windowTarget]
        )
        tmux.run(
            subcommand: .selectPane,
            arguments: [TmuxCommandRunner.targetFlag, target.paneIdentifier]
        )
        guard let chosenClient = chooseClient(forSessionNamed: target.sessionName) else { return nil }
        guard allowsClientSwitch, chosenClient.sessionName != target.sessionName else { return chosenClient }
        tmux.run(
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

    private func chooseClient(forSessionNamed sessionName: String) -> TmuxClient? {
        let listing = tmux.capture(
            subcommand: .listClients,
            arguments: [TmuxCommandRunner.formatFlag, TmuxClientListing.format]
        )
        guard let listing else { return nil }
        return TmuxClientListing.preferredClient(in: TmuxClientListing.parse(listing), attachedTo: sessionName)
    }

    private func focusItermSession(terminalDevicePath: String) -> Bool {
        guard terminals.isRunning(.iterm2) else { return false }
        let output = terminals.runItermScript(TmuxItermFocuser.itermFocusScript(terminalDevicePath: terminalDevicePath))
        return output == TmuxItermFocuser.itermFocusSuccessMarker
    }

    package static func itermFocusScript(terminalDevicePath: String) -> String {
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

    private func activateFirstRunningTerminal() {
        for terminal in TerminalBundleIdentifier.allCases {
            guard terminals.isRunning(terminal) else { continue }
            guard terminals.activate(terminal) else { continue }
            return
        }
    }
}
