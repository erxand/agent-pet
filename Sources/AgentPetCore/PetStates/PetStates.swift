import Foundation

package enum PetPhysics: String, CaseIterable, Codable {
    case ground
    case float
}

package enum PetInput: String, CaseIterable, Codable {
    case on
    case off
}

package enum PetVisibility: String, CaseIterable, Codable {
    case shown
    case hidden
}

package enum PetLevel: Equatable {
    case normal
    case above(bundleIdentifier: String)

    package static let normalWord = "normal"
    package static let aboveWord = "above"
    private static let separator: Character = " "

    package var text: String {
        switch self {
        case .normal: return PetLevel.normalWord
        case .above(let bundleIdentifier): return PetLevel.aboveWord + String(PetLevel.separator) + bundleIdentifier
        }
    }

    package init?(text: String) {
        let words = text.split(separator: PetLevel.separator, omittingEmptySubsequences: true).map { word in String(word) }
        switch words.first {
        case PetLevel.normalWord where words.count == 1:
            self = .normal
        case PetLevel.aboveWord where words.count == 2:
            self = .above(bundleIdentifier: words[1])
        default:
            return nil
        }
    }
}

package enum PetStateKind: String, CaseIterable {
    case physics
    case input
    case visibility
    case level
}

package enum PetStateSource: String, Codable {
    case defaultValue = "default"
    case trigger
    case command = "cli"
}

package struct PetStateSettings: Equatable, Codable {
    package var physics: PetPhysics?
    package var input: PetInput?
    package var visibility: PetVisibility?
    package var level: PetLevel?

    package init(physics: PetPhysics? = nil, input: PetInput? = nil, visibility: PetVisibility? = nil, level: PetLevel? = nil) {
        self.physics = physics
        self.input = input
        self.visibility = visibility
        self.level = level
    }

    package static let none = PetStateSettings()

    enum CodingKeys: String, CodingKey {
        case physics, input, visibility, level
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        physics = (try? container.decodeIfPresent(String.self, forKey: .physics)).flatMap { raw in PetPhysics(rawValue: raw) }
        input = (try? container.decodeIfPresent(String.self, forKey: .input)).flatMap { raw in PetInput(rawValue: raw) }
        visibility = (try? container.decodeIfPresent(String.self, forKey: .visibility)).flatMap { raw in PetVisibility(rawValue: raw) }
        level = (try? container.decodeIfPresent(String.self, forKey: .level)).flatMap { raw in PetLevel(text: raw) }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(physics?.rawValue, forKey: .physics)
        try container.encodeIfPresent(input?.rawValue, forKey: .input)
        try container.encodeIfPresent(visibility?.rawValue, forKey: .visibility)
        try container.encodeIfPresent(level?.text, forKey: .level)
    }

    func filling(from fallback: PetStateSettings) -> PetStateSettings {
        PetStateSettings(
            physics: physics ?? fallback.physics,
            input: input ?? fallback.input,
            visibility: visibility ?? fallback.visibility,
            level: level ?? fallback.level
        )
    }
}

package struct PetEffectiveStates: Equatable {
    package var physics: PetPhysics
    package var input: PetInput
    package var visibility: PetVisibility
    package var level: PetLevel
    package var sources: [PetStateKind: PetStateSource]

    package static let defaults = PetEffectiveStates(
        physics: .ground,
        input: .on,
        visibility: .shown,
        level: .normal,
        sources: Dictionary(uniqueKeysWithValues: PetStateKind.allCases.map { kind in (kind, PetStateSource.defaultValue) })
    )

    package static func resolve(commands: PetStateSettings, trigger: PetStateSettings) -> PetEffectiveStates {
        var states = defaults
        func source(command: Bool, triggered: Bool) -> PetStateSource {
            command ? .command : (triggered ? .trigger : .defaultValue)
        }
        states.physics = commands.physics ?? trigger.physics ?? defaults.physics
        states.input = commands.input ?? trigger.input ?? defaults.input
        states.visibility = commands.visibility ?? trigger.visibility ?? defaults.visibility
        states.level = commands.level ?? trigger.level ?? defaults.level
        states.sources = [
            .physics: source(command: commands.physics != nil, triggered: trigger.physics != nil),
            .input: source(command: commands.input != nil, triggered: trigger.input != nil),
            .visibility: source(command: commands.visibility != nil, triggered: trigger.visibility != nil),
            .level: source(command: commands.level != nil, triggered: trigger.level != nil)
        ]
        return states
    }

    package func value(of kind: PetStateKind) -> String {
        switch kind {
        case .physics: return physics.rawValue
        case .input: return input.rawValue
        case .visibility: return visibility.rawValue
        case .level: return level.text
        }
    }

    package func source(of kind: PetStateKind) -> PetStateSource {
        sources[kind] ?? .defaultValue
    }
}

package enum PetRuleLevel: String, Equatable {
    case normal
    case above
}

package struct PetFullScreenRule: Equatable {
    package let bundleIdentifiers: [String]
    package let physics: PetPhysics?
    package let input: PetInput?
    package let visibility: PetVisibility?
    package let level: PetRuleLevel?

    package init(
        bundleIdentifiers: [String],
        physics: PetPhysics? = nil,
        input: PetInput? = nil,
        visibility: PetVisibility? = nil,
        level: PetRuleLevel? = nil
    ) {
        self.bundleIdentifiers = bundleIdentifiers
        self.physics = physics
        self.input = input
        self.visibility = visibility
        self.level = level
    }

    package static func triggered(by rules: [PetFullScreenRule], summaries: [String: AppWindowSummary]) -> PetStateSettings {
        var settings = PetStateSettings.none
        for rule in rules {
            guard let matched = rule.bundleIdentifiers.first(where: { bundleIdentifier in
                summaries[bundleIdentifier]?.coversDisplay ?? false
            }) else { continue }
            let level = rule.level.map { ruleLevel -> PetLevel in
                switch ruleLevel {
                case .normal: return .normal
                case .above: return .above(bundleIdentifier: matched)
                }
            }
            settings = settings.filling(from: PetStateSettings(
                physics: rule.physics,
                input: rule.input,
                visibility: rule.visibility,
                level: level
            ))
        }
        return settings
    }
}

package enum PetInputPolicy {
    package static func acceptsInput(input: PetInput, isReturningFromSpace: Bool) -> Bool {
        guard !isReturningFromSpace else { return false }
        switch input {
        case .on: return true
        case .off: return false
        }
    }
}

package enum PetStateFile {
    private static let controlDirectoryName = "control"
    private static let commandsFileName = "states.json"
    private static let effectiveFileName = "states-effective.json"
    private static let commandsLockFileName = "states.lock"

    package static var controlDirectory: URL {
        PetPaths.stateDirectory.appendingPathComponent(controlDirectoryName, isDirectory: true)
    }

    package static var commandsFile: URL {
        controlDirectory.appendingPathComponent(commandsFileName, isDirectory: false)
    }

    package static var effectiveFile: URL {
        PetPaths.stateDirectory.appendingPathComponent(effectiveFileName, isDirectory: false)
    }

    package static var commandsLockFile: URL {
        PetPaths.stateDirectory.appendingPathComponent(commandsLockFileName, isDirectory: false)
    }

    package static func withLockedCommands<Outcome>(_ transform: (inout PetStateSettings) -> Outcome) -> Outcome {
        let lock = PetRecordLock(lockFileURL: commandsLockFile)
        lock?.acquireExclusively()
        defer { lock?.release() }
        var commands = loadCommands()
        return transform(&commands)
    }

    package static func loadCommands() -> PetStateSettings {
        guard let payload = try? Data(contentsOf: commandsFile),
              let settings = try? JSONDecoder().decode(PetStateSettings.self, from: payload) else { return .none }
        return settings
    }

    @discardableResult
    package static func saveCommands(_ settings: PetStateSettings) -> Bool {
        guard settings != .none else {
            clearCommands()
            return true
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let payload = try? encoder.encode(settings) else { return false }
        return writeAtomically(payload, to: commandsFile)
    }

    package static func clearCommands() {
        try? FileManager.default.removeItem(at: commandsFile)
    }

    package struct EffectiveEntry: Codable, Equatable {
        package let value: String
        package let source: PetStateSource
    }

    package static func entries(of states: PetEffectiveStates) -> [String: EffectiveEntry] {
        Dictionary(uniqueKeysWithValues: PetStateKind.allCases.map { kind in
            (kind.rawValue, EffectiveEntry(value: states.value(of: kind), source: states.source(of: kind)))
        })
    }

    package static func saveEffective(_ states: PetEffectiveStates) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let payload = try? encoder.encode(entries(of: states)) else { return }
        writeAtomically(payload, to: effectiveFile)
    }

    package static func loadEffective() -> [String: EffectiveEntry]? {
        guard let payload = try? Data(contentsOf: effectiveFile) else { return nil }
        return try? JSONDecoder().decode([String: EffectiveEntry].self, from: payload)
    }

    @discardableResult
    private static func writeAtomically(_ payload: Data, to fileURL: URL) -> Bool {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let temporary = directory.appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString)")
            try payload.write(to: temporary)
            guard rename(temporary.path, fileURL.path) == 0 else {
                try? FileManager.default.removeItem(at: temporary)
                return false
            }
            return true
        } catch {
            return false
        }
    }
}
