import Foundation

package enum FocuserConfiguration: Equatable {
    case tmuxIterm
    case command(arguments: [String])
}

package enum ColorSyncKind: String, Equatable {
    case tmuxColor = "tmux-color"
    case none
}

package enum LabelPlacement: String, Equatable {
    case pill
    case nametag
}

package struct AgentPetConfiguration: Equatable {
    package static let defaultSessionDirectoryPatterns = ["~/.claude/sessions"]

    package static let defaults = AgentPetConfiguration(
        focuser: .tmuxIterm,
        sessionDirectoryPatterns: defaultSessionDirectoryPatterns,
        colorSync: .tmuxColor
    )

    package var focuser: FocuserConfiguration
    package var sessionDirectoryPatterns: [String]
    package var colorSync: ColorSyncKind
    package var labelPlacement: LabelPlacement
    package var disambiguatesLabels: Bool
    package var reservedSprites: [String]

    package init(
        focuser: FocuserConfiguration,
        sessionDirectoryPatterns: [String],
        colorSync: ColorSyncKind,
        labelPlacement: LabelPlacement = .pill,
        disambiguatesLabels: Bool = false,
        reservedSprites: [String] = []
    ) {
        self.focuser = focuser
        self.sessionDirectoryPatterns = sessionDirectoryPatterns
        self.colorSync = colorSync
        self.labelPlacement = labelPlacement
        self.disambiguatesLabels = disambiguatesLabels
        self.reservedSprites = reservedSprites
    }
}

package enum FocuserKindName: String {
    case tmuxIterm = "tmux-iterm"
    case command
}

package enum ConfigurationFile {
    package static let fileName = "config.json"

    package static func path(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let overridden = environment[EnvironmentVariableName.configurationPath], !overridden.isEmpty {
            return URL(fileURLWithPath: overridden, isDirectory: false)
        }
        return PetPaths.stateDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    package static func load(environment: [String: String] = ProcessInfo.processInfo.environment) -> AgentPetConfiguration {
        load(from: path(environment: environment))
    }

    package static func load(from fileURL: URL) -> AgentPetConfiguration {
        guard let payload = try? Data(contentsOf: fileURL) else { return .defaults }
        return parse(payload)
    }

    package static func parse(_ payload: Data) -> AgentPetConfiguration {
        guard let raw = try? JSONDecoder().decode(RawConfiguration.self, from: payload) else { return .defaults }
        var configuration = AgentPetConfiguration.defaults
        if let focuser = raw.focuser?.resolved { configuration.focuser = focuser }
        if let patterns = raw.sessionDirectories, !patterns.isEmpty { configuration.sessionDirectoryPatterns = patterns }
        if let colorSync = raw.colorSync.flatMap({ rawValue in ColorSyncKind(rawValue: rawValue) }) {
            configuration.colorSync = colorSync
        }
        if let labelPlacement = raw.labelPlacement.flatMap({ rawValue in LabelPlacement(rawValue: rawValue) }) {
            configuration.labelPlacement = labelPlacement
        }
        if let disambiguatesLabels = raw.disambiguateLabels { configuration.disambiguatesLabels = disambiguatesLabels }
        if let reservedSprites = raw.reservedSprites { configuration.reservedSprites = reservedSprites }
        return configuration
    }

    package static func modificationDate(of fileURL: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return attributes?[.modificationDate] as? Date
    }
}

private struct RawFocuser: Decodable {
    let kind: String?
    let command: [String]?

    var resolved: FocuserConfiguration? {
        guard let kind, let kindName = FocuserKindName(rawValue: kind) else { return nil }
        switch kindName {
        case .tmuxIterm:
            return .tmuxIterm
        case .command:
            let arguments = (command ?? []).filter { argument in !argument.isEmpty }
            guard !arguments.isEmpty else { return nil }
            return .command(arguments: arguments)
        }
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case command
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try? container.decodeIfPresent(String.self, forKey: .kind)
        command = try? container.decodeIfPresent([String].self, forKey: .command)
    }
}

private struct RawConfiguration: Decodable {
    let focuser: RawFocuser?
    let sessionDirectories: [String]?
    let colorSync: String?
    let labelPlacement: String?
    let disambiguateLabels: Bool?
    let reservedSprites: [String]?

    enum CodingKeys: String, CodingKey {
        case focuser
        case sessionDirectories
        case colorSync
        case labelPlacement
        case disambiguateLabels
        case reservedSprites
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        focuser = try? container.decodeIfPresent(RawFocuser.self, forKey: .focuser)
        sessionDirectories = (try? container.decodeIfPresent([LenientString].self, forKey: .sessionDirectories))?
            .compactMap { entry in entry.value }
            .filter { pattern in !pattern.isEmpty }
        colorSync = try? container.decodeIfPresent(String.self, forKey: .colorSync)
        labelPlacement = try? container.decodeIfPresent(String.self, forKey: .labelPlacement)
        disambiguateLabels = try? container.decodeIfPresent(Bool.self, forKey: .disambiguateLabels)
        reservedSprites = (try? container.decodeIfPresent([LenientString].self, forKey: .reservedSprites))?
            .compactMap { entry in entry.value }
            .filter { packName in !packName.isEmpty }
    }
}

private struct LenientString: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(String.self)
    }
}
