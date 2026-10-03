import Foundation

enum PreviewCommand {
    private static let defaultDurationInSeconds: Double = 20
    private static let previewIdentifierLength = 8
    private static let uuidSeparator = "-"

    static func run(flags: ParsedFlags) -> Int32 {
        do {
            let overrides = try FlagParsing.identityOverrides(in: flags)
            let mood = try FlagParsing.mood(in: flags) ?? .ready
            return startPreview(overrides: overrides, mood: mood, flags: flags)
        } catch let failure as FlagParseFailure {
            return failure.report()
        } catch {
            return CommandFeedback.reportUsage()
        }
    }

    private static func startPreview(
        overrides: PetIdentityOverrides,
        mood: PetMood,
        flags: ParsedFlags
    ) -> Int32 {
        let durationInSeconds = flags.value(for: .seconds).flatMap { rawValue in Double(rawValue) }
            ?? defaultDurationInSeconds
        let sessionId = PetSession.previewSessionIdPrefix + shortIdentifier()

        var record = overrides.applied(to: PetSession.newlyEnrolled(sessionId: sessionId))
        record.nickname = record.nickname ?? PetSession.previewNickname
        if record.sprite == nil {
            record.sprite = AgentPetContracts.loaded().spriteStrategy.spriteName(forNewSessionId: sessionId)
        }
        if record.accent == nil, let spriteName = record.sprite {
            record.accent = SpritePackAccent.accent(forPackNamed: spriteName)
        }
        record.visible = true
        record.mood = mood
        record.updatedAt = Date().timeIntervalSince1970

        let store = PetSessionStore()
        store.save(record)
        DaemonCommand.ensureRunning()
        print(
            "preview \(sessionId), sprite \(record.sprite ?? SpritePackLoader.defaultPackName), "
                + "accent \(record.resolvedAccent.rawValue), mood \(mood.rawValue), "
                + "\(formattedDuration(durationInSeconds)) s"
        )

        Thread.sleep(forTimeInterval: max(0, durationInSeconds))
        store.delete(sessionId: sessionId)
        return ExitCode.success
    }

    private static func shortIdentifier() -> String {
        let compact = UUID().uuidString.replacingOccurrences(of: uuidSeparator, with: "").lowercased()
        return String(compact.prefix(previewIdentifierLength))
    }

    private static func formattedDuration(_ durationInSeconds: Double) -> String {
        String(format: "%.0f", durationInSeconds)
    }
}
