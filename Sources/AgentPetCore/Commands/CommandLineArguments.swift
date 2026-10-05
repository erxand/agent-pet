import Foundation

enum CommandName: String, CaseIterable {
    case daemon
    case ensureDaemon = "ensure-daemon"
    case on
    case off
    case show
    case hide
    case release
    case remove
    case status
    case hook
    case preview
    case focus
    case clearSubagents = "clear-subagents"
    case scanTranscript = "scan-transcript"
    case render
    case packs
    case demo
}

enum CommandFlag: String, CaseIterable {
    case session = "--session"
    case nickname = "--nickname"
    case label = "--label"
    case accent = "--accent"
    case mood = "--mood"
    case message = "--message"
    case seconds = "--seconds"
    case agent = "--agent"
    case tmux = "--tmux"
    case pid = "--pid"
    case sprite = "--sprite"
    case path = "--path"
    case from = "--from"
    case focusTarget = "--focus-target"
    case group = "--group"
    case pack = "--pack"
    case animation = "--animation"
    case frame = "--frame"
    case grace = "--grace"
    case scene = "--scene"
    case speed = "--speed"
    case snapshot = "--snapshot"
}

struct ParsedFlags {
    private static let inlineValueSeparator: Character = "="

    private let valuesByFlag: [CommandFlag: String]
    private let presentSwitches: Set<CommandSwitch>

    init(arguments: [String]) {
        var collectedValues: [CommandFlag: String] = [:]
        var collectedSwitches: Set<CommandSwitch> = []
        var remaining = arguments
        while let token = remaining.first {
            remaining.removeFirst()
            if let inlineSeparatorIndex = token.firstIndex(of: ParsedFlags.inlineValueSeparator),
               let inlineFlag = CommandFlag(rawValue: String(token[token.startIndex..<inlineSeparatorIndex])) {
                collectedValues[inlineFlag] = String(token[token.index(after: inlineSeparatorIndex)...])
                continue
            }
            if let commandSwitch = CommandSwitch(rawValue: token) {
                collectedSwitches.insert(commandSwitch)
                continue
            }
            guard let flag = CommandFlag(rawValue: token) else { continue }
            guard let nextToken = remaining.first else { continue }
            remaining.removeFirst()
            collectedValues[flag] = nextToken
        }
        valuesByFlag = collectedValues
        presentSwitches = collectedSwitches
    }

    func value(for flag: CommandFlag) -> String? {
        guard let value = valuesByFlag[flag], !value.isEmpty else { return nil }
        return value
    }

    func isPresent(_ commandSwitch: CommandSwitch) -> Bool {
        presentSwitches.contains(commandSwitch)
    }
}

enum ExitCode {
    static let success: Int32 = 0
    static let unavailable: Int32 = 1
    static let usage: Int32 = 2
}

enum RecordSelection {
    static func sessionIds(flags: ParsedFlags, store: PetSessionStore = PetSessionStore()) -> [String]? {
        if let explicit = flags.value(for: .session) { return [explicit] }
        if let focusTarget = flags.value(for: .focusTarget) {
            return store.list()
                .filter { record in record.focusTarget == focusTarget }
                .map { record in record.sessionId }
        }
        if let rawProcessIdentifier = flags.value(for: .pid) {
            guard let processIdentifier = Int32(rawProcessIdentifier) else { return [] }
            return store.list()
                .filter { record in record.pid == processIdentifier }
                .map { record in record.sessionId }
        }
        return SessionIdentifierResolver.resolve(flags: flags).map { sessionId in [sessionId] }
    }
}

enum SessionIdentifierResolver {
    static func resolve(flags: ParsedFlags) -> String? {
        if let explicit = flags.value(for: .session) { return explicit }
        let fromEnvironment = ProcessInfo.processInfo.environment[EnvironmentVariableName.claudeCodeSessionId]
        if let fromEnvironment, !fromEnvironment.isEmpty { return fromEnvironment }
        return nil
    }
}
