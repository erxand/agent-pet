import Foundation

enum SessionCommands {
    static func turnOn(flags: ParsedFlags) -> Int32 {
        guard let sessionId = SessionIdentifierResolver.resolve(flags: flags) else {
            return CommandFeedback.reportMissingSession()
        }
        do {
            let enrolled = PetEnrollment.enroll(
                sessionId: sessionId,
                overrides: try FlagParsing.identityOverrides(in: flags)
            )
            DaemonCommand.ensureRunning()
            let label = PetLabel.resolve(session: enrolled, claudeSession: nil)
            print("pet on for \(label), accent \(enrolled.resolvedAccent.rawValue)")
            if let target = promptBarColorSyncTarget(session: enrolled, flags: flags) {
                PromptBarColorSync.applyAccent(enrolled.resolvedAccent, target: target)
            }
            return ExitCode.success
        } catch let failure as FlagParseFailure {
            return failure.report()
        } catch {
            return CommandFeedback.reportUsage()
        }
    }

    static func turnOff(flags: ParsedFlags) -> Int32 {
        guard let sessionId = SessionIdentifierResolver.resolve(flags: flags) else {
            return CommandFeedback.reportMissingSession()
        }
        guard let disabled = PetEnrollment.disable(sessionId: sessionId) else {
            return ExitCode.success
        }
        if let target = promptBarColorSyncTarget(session: disabled, flags: flags) {
            PromptBarColorSync.applyDefaultColor(target: target)
        }
        return ExitCode.success
    }

    static func show(flags: ParsedFlags) -> Int32 {
        guard let sessionId = SessionIdentifierResolver.resolve(flags: flags) else {
            return CommandFeedback.reportMissingSession()
        }
        do {
            let overrides = try FlagParsing.identityOverrides(in: flags)
            let requestedMood = try FlagParsing.mood(in: flags)
            if overrides.hasAnyOverride {
                PetEnrollment.applyOverrides(sessionId: sessionId, overrides: overrides)
            }
            let snapshot = PetTurnState.show(
                sessionId: sessionId,
                mood: requestedMood,
                message: flags.value(for: .message)
            )
            guard snapshot.visible else { return ExitCode.success }
            DaemonCommand.ensureRunning()
            return ExitCode.success
        } catch let failure as FlagParseFailure {
            return failure.report()
        } catch {
            return CommandFeedback.reportUsage()
        }
    }

    static func hide(flags: ParsedFlags) -> Int32 {
        guard let sessionId = SessionIdentifierResolver.resolve(flags: flags) else {
            return CommandFeedback.reportMissingSession()
        }
        PetTurnState.hide(sessionId: sessionId)
        return ExitCode.success
    }

    static func remove(flags: ParsedFlags) -> Int32 {
        guard let sessionId = SessionIdentifierResolver.resolve(flags: flags) else {
            return CommandFeedback.reportMissingSession()
        }
        PetTurnState.remove(sessionId: sessionId)
        return ExitCode.success
    }

    static func clearSubagents(flags: ParsedFlags) -> Int32 {
        guard let sessionId = SessionIdentifierResolver.resolve(flags: flags) else {
            return CommandFeedback.reportMissingSession()
        }
        guard let droppedCount = PetSubagentTracking.clear(sessionId: sessionId) else {
            return CommandFeedback.reportMissingRecord(sessionId)
        }
        print("cleared \(droppedCount) tracked subagents for \(sessionId)")
        return ExitCode.success
    }

    private static func promptBarColorSyncTarget(session: PetSession, flags: ParsedFlags) -> TmuxTarget? {
        guard !flags.isPresent(.noColorSync) else { return nil }
        switch session.agent {
        case .claudeCode:
            return session.parsedTmuxTarget
        case .pi:
            return nil
        }
    }
}
