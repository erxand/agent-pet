import AppKit

enum TerminalBundleIdentifier: String, CaseIterable {
    case iterm2 = "com.googlecode.iterm2"
    case appleTerminal = "com.apple.Terminal"
    case ghostty = "com.mitchellh.ghostty"
}

enum SessionFocuser {
    static func focus(tmuxTarget: TmuxTarget?) {
        if let tmuxTarget {
            selectTmuxPane(tmuxTarget)
        }
        activateFirstRunningTerminal()
    }

    private static func selectTmuxPane(_ target: TmuxTarget) {
        TmuxCommandRunner.run(
            subcommand: .selectWindow,
            arguments: [TmuxCommandRunner.targetFlag, target.windowTarget]
        )
        TmuxCommandRunner.run(
            subcommand: .selectPane,
            arguments: [TmuxCommandRunner.targetFlag, target.paneIdentifier]
        )
        TmuxCommandRunner.run(
            subcommand: .switchClient,
            arguments: [TmuxCommandRunner.targetFlag, target.sessionName]
        )
    }

    private static func activateFirstRunningTerminal() {
        for bundleIdentifier in TerminalBundleIdentifier.allCases {
            let runningInstances = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier.rawValue
            )
            guard !runningInstances.isEmpty else { continue }
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
