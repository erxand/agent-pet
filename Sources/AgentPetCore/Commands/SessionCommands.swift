import Foundation

enum SessionCommands {
    static func turnOn(flags: ParsedFlags) -> Int32 {
        guard let sessionId = SessionIdentifierResolver.resolve(flags: flags) else {
            return CommandFeedback.reportMissingSession()
        }
        do {
            let contracts = AgentPetContracts.loaded()
            let enrolled = PetEnrollment.enroll(
                sessionId: sessionId,
                overrides: try FlagParsing.identityOverrides(in: flags),
                spriteStrategy: contracts.spriteStrategy
            )
            DaemonCommand.ensureRunning()
            let label = PetLabel.resolve(session: enrolled, claudeSession: nil)
            let spriteName = enrolled.sprite ?? SpritePackLoader.defaultPackName
            print("pet on for \(label), sprite \(spriteName), accent \(enrolled.resolvedAccent.rawValue)")
            if !flags.isPresent(.noColorSync) {
                contracts.colorSync.applyAccent(enrolled.resolvedAccent, to: enrolled)
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
        if !flags.isPresent(.noColorSync) {
            AgentPetContracts.loaded().colorSync.resetColor(of: disabled)
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
        guard let sessionIds = RecordSelection.sessionIds(flags: flags) else {
            return CommandFeedback.reportMissingSession()
        }
        for sessionId in sessionIds {
            PetTurnState.hide(sessionId: sessionId)
            LeadGroupQuieting.hideReadyMembers(ofLead: sessionId)
        }
        return ExitCode.success
    }

    static func release(flags: ParsedFlags) -> Int32 {
        guard let sessionIds = RecordSelection.sessionIds(flags: flags) else {
            return CommandFeedback.reportMissingSession()
        }
        let grace = flags.value(for: .grace).flatMap { rawValue in TimeInterval(rawValue) }
        var anyVisible = false
        for sessionId in sessionIds where PetTurnState.release(sessionId: sessionId, grace: grace).visible {
            anyVisible = true
        }
        if anyVisible { DaemonCommand.ensureRunning() }
        return ExitCode.success
    }

    static func remove(flags: ParsedFlags) -> Int32 {
        guard let sessionIds = RecordSelection.sessionIds(flags: flags) else {
            return CommandFeedback.reportMissingSession()
        }
        for sessionId in sessionIds {
            PetTurnState.remove(sessionId: sessionId)
        }
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
}
