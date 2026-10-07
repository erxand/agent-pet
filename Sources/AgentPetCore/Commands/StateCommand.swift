import Foundation

enum StateCommand {
    static let automaticWord = "auto"

    static func run(kind: PetStateKind, arguments: [String]) -> Int32 {
        guard let first = arguments.first else { return reportInvalid(kind: kind, given: nil) }
        return PetStateFile.withLockedCommands { commands in
            let shown: String
            if first == automaticWord {
                guard arguments.count == 1 else { return reportInvalid(kind: kind, given: arguments.joined(separator: " ")) }
                clear(kind, in: &commands)
                shown = automaticWord
            } else {
                guard let value = apply(kind, words: arguments, to: &commands) else {
                    return reportInvalid(kind: kind, given: arguments.joined(separator: " "))
                }
                shown = value
            }
            guard PetStateFile.saveCommands(commands) else {
                CommandFeedback.writeToStandardError("cannot write \(PetStateFile.commandsFile.path).")
                return ExitCode.failure
            }
            print("\(kind.rawValue): \(shown)")
            return ExitCode.success
        }
    }

    static func validValues(of kind: PetStateKind) -> String {
        let values: [String]
        switch kind {
        case .physics: values = PetPhysics.allCases.map { physics in physics.rawValue }
        case .input: values = PetInput.allCases.map { input in input.rawValue }
        case .visibility: values = PetVisibility.allCases.map { visibility in visibility.rawValue }
        case .level: values = [PetLevel.normalWord, PetLevel.aboveWord + " <bundle id>"]
        }
        return (values + [automaticWord]).joined(separator: ", ")
    }

    private static func clear(_ kind: PetStateKind, in commands: inout PetStateSettings) {
        switch kind {
        case .physics: commands.physics = nil
        case .input: commands.input = nil
        case .visibility: commands.visibility = nil
        case .level: commands.level = nil
        }
    }

    private static func apply(_ kind: PetStateKind, words: [String], to commands: inout PetStateSettings) -> String? {
        let text = words.joined(separator: " ")
        switch kind {
        case .physics:
            guard words.count == 1, let physics = PetPhysics(rawValue: text) else { return nil }
            commands.physics = physics
            return physics.rawValue
        case .input:
            guard words.count == 1, let input = PetInput(rawValue: text) else { return nil }
            commands.input = input
            return input.rawValue
        case .visibility:
            guard words.count == 1, let visibility = PetVisibility(rawValue: text) else { return nil }
            commands.visibility = visibility
            return visibility.rawValue
        case .level:
            guard let level = PetLevel(text: text) else { return nil }
            commands.level = level
            return level.text
        }
    }

    private static func reportInvalid(kind: PetStateKind, given: String?) -> Int32 {
        let prefix = given.map { value in "unknown \(kind.rawValue) \(value). " } ?? "\(kind.rawValue) needs a value. "
        CommandFeedback.writeToStandardError(prefix + "Valid values: \(validValues(of: kind)).")
        return ExitCode.usage
    }
}
