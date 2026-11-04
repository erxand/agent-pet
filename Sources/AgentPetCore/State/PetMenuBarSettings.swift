import Foundation

/// What the menu bar icon's two toggles remember. Pet state commands are cleared whenever
/// the daemon starts, so "Hide pets" keeps its own copy here to outlive a restart.
package struct PetMenuBarSettings: Codable, Equatable {
    package static let fileName = "menu-bar.json"

    package var hidesPets: Bool
    package var opensAtLogin: Bool

    package init(hidesPets: Bool = false, opensAtLogin: Bool = true) {
        self.hidesPets = hidesPets
        self.opensAtLogin = opensAtLogin
    }

    package static func file(in directory: URL = PetPaths.stateDirectory) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    package static func load(from file: URL = PetMenuBarSettings.file()) -> PetMenuBarSettings {
        guard let payload = try? Data(contentsOf: file),
              let settings = try? JSONDecoder().decode(PetMenuBarSettings.self, from: payload) else { return PetMenuBarSettings() }
        return settings
    }

    @discardableResult
    package func save(to file: URL = PetMenuBarSettings.file()) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let payload = try? encoder.encode(self) else { return false }
        return (try? payload.write(to: file, options: .atomic)) != nil
    }

    enum CodingKeys: String, CodingKey {
        case hidesPets, opensAtLogin
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hidesPets = (try? container.decodeIfPresent(Bool.self, forKey: .hidesPets)) ?? false
        opensAtLogin = (try? container.decodeIfPresent(Bool.self, forKey: .opensAtLogin)) ?? true
    }
}

/// Whether macOS starts the daemon at login, which is the LaunchAgent being enabled.
/// launchd remembers a disabled service across restarts and the running daemon keeps
/// running. An installer that enables the service again is undone when the daemon next starts.
package enum PetLoginItem {
    package static func apply(
        opensAtLogin: Bool,
        launchctl: (LaunchctlSubcommand, [String]) -> LaunchctlOutcome = { subcommand, arguments in
            LaunchAgent.runLaunchctl(subcommand: subcommand, arguments: arguments)
        }
    ) -> Bool {
        guard LaunchAgent.isInstalled else { return false }
        return launchctl(opensAtLogin ? .enable : .disable, [LaunchAgent.serviceTarget]) == .succeeded
    }

    /// True when the toggle turned login start off. launchd then refuses to start the service
    /// at all, so a session's hook starts the daemon on its own instead.
    package static func isTurnedOff(
        configuration: () -> AgentPetConfiguration = { ConfigurationFile.load() },
        settings: () -> PetMenuBarSettings = { PetMenuBarSettings.load() }
    ) -> Bool {
        configuration().showsMenuBarIcon && !settings().opensAtLogin
    }
}
