import Foundation

enum FlagParseFailure: Error {
    case unknownAccent(String)
    case unknownMood(String)
    case unknownAgent(String)
    case unknownProcessIdentifier(String)
    case invalidByteOffset(String)

    func report() -> Int32 {
        switch self {
        case .unknownAccent(let rawValue): return CommandFeedback.reportUnknownAccent(rawValue)
        case .unknownMood(let rawValue): return CommandFeedback.reportUnknownMood(rawValue)
        case .unknownAgent(let rawValue): return CommandFeedback.reportUnknownAgent(rawValue)
        case .unknownProcessIdentifier(let rawValue): return CommandFeedback.reportUnknownProcessIdentifier(rawValue)
        case .invalidByteOffset(let rawValue): return CommandFeedback.reportInvalidByteOffset(rawValue)
        }
    }
}

enum FlagParsing {
    static let startOfFileByteOffset = 0

    static func byteOffset(in flags: ParsedFlags) throws -> Int {
        guard let rawValue = flags.value(for: .from) else { return startOfFileByteOffset }
        guard let byteOffset = Int(rawValue), byteOffset >= startOfFileByteOffset else {
            throw FlagParseFailure.invalidByteOffset(rawValue)
        }
        return byteOffset
    }

    static func accent(in flags: ParsedFlags) throws -> AccentColor? {
        guard let rawValue = flags.value(for: .accent) else { return nil }
        guard let accent = AccentColor(rawValue: rawValue) else {
            throw FlagParseFailure.unknownAccent(rawValue)
        }
        return accent
    }

    static func mood(in flags: ParsedFlags) throws -> PetMood? {
        guard let rawValue = flags.value(for: .mood) else { return nil }
        guard let mood = PetMood(rawValue: rawValue) else {
            throw FlagParseFailure.unknownMood(rawValue)
        }
        return mood
    }

    static func agent(in flags: ParsedFlags) throws -> PetAgent? {
        guard let rawValue = flags.value(for: .agent) else { return nil }
        guard let agent = PetAgent(rawValue: rawValue) else {
            throw FlagParseFailure.unknownAgent(rawValue)
        }
        return agent
    }

    static func processIdentifier(in flags: ParsedFlags) throws -> Int32? {
        guard let rawValue = flags.value(for: .pid) else { return nil }
        guard let processIdentifier = Int32(rawValue) else {
            throw FlagParseFailure.unknownProcessIdentifier(rawValue)
        }
        return processIdentifier
    }

    static func identityOverrides(in flags: ParsedFlags) throws -> PetIdentityOverrides {
        PetIdentityOverrides(
            nickname: flags.value(for: .nickname),
            label: flags.value(for: .label),
            accent: try accent(in: flags),
            agent: try agent(in: flags),
            tmuxTarget: flags.value(for: .tmux),
            pid: try processIdentifier(in: flags),
            sprite: flags.value(for: .sprite)
        )
    }
}
