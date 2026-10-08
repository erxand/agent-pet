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
    package static let defaultSettleSeconds: TimeInterval = 0
    package static let maximumGroundGap: Double = 200

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
    package var spriteDirectories: [String]
    package var settleSeconds: TimeInterval
    package var holdsWhileBusy: Bool
    package var paintsAccentInks: Bool
    package var divesOnExit: Bool
    package var subagentToolsKeepNeedsInput: Bool
    package var display: DisplayChoice
    package var fullScreenRules: [PetFullScreenRule]
    package var hidesLabelsWhileFloating: Bool
    package var standsOnDock: Bool
    package var groundGap: CGFloat?

    package init(
        focuser: FocuserConfiguration,
        sessionDirectoryPatterns: [String],
        colorSync: ColorSyncKind,
        labelPlacement: LabelPlacement = .pill,
        disambiguatesLabels: Bool = false,
        reservedSprites: [String] = [],
        spriteDirectories: [String] = [],
        settleSeconds: TimeInterval = AgentPetConfiguration.defaultSettleSeconds,
        holdsWhileBusy: Bool = false,
        paintsAccentInks: Bool = false,
        divesOnExit: Bool = false,
        subagentToolsKeepNeedsInput: Bool = false,
        display: DisplayChoice = .focused,
        fullScreenRules: [PetFullScreenRule] = [],
        hidesLabelsWhileFloating: Bool = false,
        standsOnDock: Bool = true,
        groundGap: CGFloat? = nil
    ) {
        self.focuser = focuser
        self.sessionDirectoryPatterns = sessionDirectoryPatterns
        self.colorSync = colorSync
        self.labelPlacement = labelPlacement
        self.disambiguatesLabels = disambiguatesLabels
        self.reservedSprites = reservedSprites
        self.spriteDirectories = spriteDirectories
        self.settleSeconds = settleSeconds
        self.holdsWhileBusy = holdsWhileBusy
        self.paintsAccentInks = paintsAccentInks
        self.divesOnExit = divesOnExit
        self.subagentToolsKeepNeedsInput = subagentToolsKeepNeedsInput
        self.display = display
        self.fullScreenRules = fullScreenRules
        self.hidesLabelsWhileFloating = hidesLabelsWhileFloating
        self.standsOnDock = standsOnDock
        self.groundGap = groundGap
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
        if let spriteDirectories = raw.spriteDirectories { configuration.spriteDirectories = spriteDirectories }
        if let settleSeconds = raw.settleSeconds, settleSeconds.isFinite, settleSeconds >= 0 {
            configuration.settleSeconds = settleSeconds
        }
        if let holdsWhileBusy = raw.holdWhileBusy { configuration.holdsWhileBusy = holdsWhileBusy }
        if let paintsAccentInks = raw.accentInks { configuration.paintsAccentInks = paintsAccentInks }
        if let divesOnExit = raw.diveOnExit { configuration.divesOnExit = divesOnExit }
        if let keepsNeedsInput = raw.subagentToolsKeepNeedsInput {
            configuration.subagentToolsKeepNeedsInput = keepsNeedsInput
        }
        if let display = raw.display.flatMap({ rawValue in DisplayChoice(configValue: rawValue) }) {
            configuration.display = display
        }
        if let rules = raw.whenFullScreen {
            configuration.fullScreenRules = rules.compactMap { rule in rule.resolved }
        }
        if let hidesLabels = raw.hideLabelsWhileFloating { configuration.hidesLabelsWhileFloating = hidesLabels }
        if let standsOnDock = raw.dockGround { configuration.standsOnDock = standsOnDock }
        if let groundGap = raw.groundGap, groundGap.isFinite, groundGap >= 0, groundGap <= AgentPetConfiguration.maximumGroundGap {
            configuration.groundGap = CGFloat(groundGap)
        }
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
    let spriteDirectories: [String]?
    let settleSeconds: Double?
    let holdWhileBusy: Bool?
    let accentInks: Bool?
    let diveOnExit: Bool?
    let subagentToolsKeepNeedsInput: Bool?
    let display: String?
    let whenFullScreen: [RawFullScreenRule]?
    let hideLabelsWhileFloating: Bool?
    let dockGround: Bool?
    let groundGap: Double?

    enum CodingKeys: String, CodingKey {
        case focuser
        case sessionDirectories
        case colorSync
        case labelPlacement
        case disambiguateLabels
        case reservedSprites
        case spriteDirectories
        case settleSeconds
        case holdWhileBusy
        case accentInks
        case diveOnExit
        case subagentToolsKeepNeedsInput
        case display
        case whenFullScreen
        case hideLabelsWhileFloating
        case dockGround
        case groundGap
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settleSeconds = try? container.decodeIfPresent(Double.self, forKey: .settleSeconds)
        holdWhileBusy = try? container.decodeIfPresent(Bool.self, forKey: .holdWhileBusy)
        accentInks = try? container.decodeIfPresent(Bool.self, forKey: .accentInks)
        diveOnExit = try? container.decodeIfPresent(Bool.self, forKey: .diveOnExit)
        subagentToolsKeepNeedsInput = try? container.decodeIfPresent(Bool.self, forKey: .subagentToolsKeepNeedsInput)
        focuser = try? container.decodeIfPresent(RawFocuser.self, forKey: .focuser)
        sessionDirectories = (try? container.decodeIfPresent([LenientString].self, forKey: .sessionDirectories))?
            .compactMap { entry in entry.value }
            .filter { pattern in !pattern.isEmpty }
        colorSync = try? container.decodeIfPresent(String.self, forKey: .colorSync)
        display = try? container.decodeIfPresent(String.self, forKey: .display)
        whenFullScreen = try? container.decodeIfPresent([RawFullScreenRule].self, forKey: .whenFullScreen)
        hideLabelsWhileFloating = try? container.decodeIfPresent(Bool.self, forKey: .hideLabelsWhileFloating)
        dockGround = try? container.decodeIfPresent(Bool.self, forKey: .dockGround)
        groundGap = try? container.decodeIfPresent(Double.self, forKey: .groundGap)
        labelPlacement = try? container.decodeIfPresent(String.self, forKey: .labelPlacement)
        disambiguateLabels = try? container.decodeIfPresent(Bool.self, forKey: .disambiguateLabels)
        reservedSprites = (try? container.decodeIfPresent([LenientString].self, forKey: .reservedSprites))?
            .compactMap { entry in entry.value }
            .filter { packName in !packName.isEmpty }
        spriteDirectories = (try? container.decodeIfPresent([LenientString].self, forKey: .spriteDirectories))?
            .compactMap { entry in entry.value }
            .filter { path in !path.isEmpty }
    }
}

private struct LenientString: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(String.self)
    }
}

private struct RawFullScreenRule: Decodable {
    let bundleIds: [String]
    let apply: RawRuleStates?

    enum CodingKeys: String, CodingKey {
        case bundleIds
        case apply
    }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        bundleIds = ((try? container?.decodeIfPresent([LenientString].self, forKey: .bundleIds)) ?? [])
            .compactMap { entry in entry.value }
            .filter { bundleIdentifier in !bundleIdentifier.isEmpty }
        apply = try? container?.decodeIfPresent(RawRuleStates.self, forKey: .apply)
    }

    var resolved: PetFullScreenRule? {
        guard !bundleIds.isEmpty, let apply else { return nil }
        let rule = PetFullScreenRule(
            bundleIdentifiers: bundleIds,
            physics: apply.physics.flatMap { raw in PetPhysics(rawValue: raw) },
            input: apply.input.flatMap { raw in PetInput(rawValue: raw) },
            visibility: apply.visibility.flatMap { raw in PetVisibility(rawValue: raw) },
            level: apply.level.flatMap { raw in PetRuleLevel(rawValue: raw) }
        )
        guard rule.physics != nil || rule.input != nil || rule.visibility != nil || rule.level != nil else { return nil }
        return rule
    }
}

private struct RawRuleStates: Decodable {
    let physics: String?
    let input: String?
    let visibility: String?
    let level: String?

    enum CodingKeys: String, CodingKey {
        case physics, input, visibility, level
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        physics = try? container.decodeIfPresent(String.self, forKey: .physics)
        input = try? container.decodeIfPresent(String.self, forKey: .input)
        visibility = try? container.decodeIfPresent(String.self, forKey: .visibility)
        level = try? container.decodeIfPresent(String.self, forKey: .level)
    }
}
