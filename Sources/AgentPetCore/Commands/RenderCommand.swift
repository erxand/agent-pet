import Foundation

enum RenderCommand {
    private static let firstFrameIndex = 0

    static func run(flags: ParsedFlags) -> Int32 {
        guard let packName = flags.value(for: .pack) else {
            return CommandFeedback.reportMissingPack()
        }
        let animationName = flags.value(for: .animation) ?? SpriteAnimationName.idle.rawValue
        guard let animation = SpriteAnimationName(rawValue: animationName) else {
            return CommandFeedback.reportUnknownAnimation(animationName)
        }
        let accent: AccentColor?
        do {
            accent = try FlagParsing.accent(in: flags)
        } catch let failure as FlagParseFailure {
            return failure.report()
        } catch {
            return ExitCode.usage
        }
        let loader = SpritePackLoader()
        let outcome = loader.load(packNamed: packName)
        if case .notDownloaded(let undownloaded) = outcome {
            loader.residency.requestDownload(undownloaded)
            return CommandFeedback.reportPackNotDownloaded(packName)
        }
        guard let sheet = sheet(from: outcome, packName: packName, accent: accent) else {
            return CommandFeedback.reportUnknownPack(packName)
        }
        let frames = animation.frames(in: sheet)
        let rawFrame = flags.value(for: .frame) ?? String(firstFrameIndex)
        guard let frameIndex = Int(rawFrame), frames.indices.contains(frameIndex) else {
            return CommandFeedback.reportUnknownFrame(rawFrame, animation: animation, frameCount: frames.count)
        }
        FileHandle.standardOutput.write(Data(TerminalSpriteRenderer.render(frame: frames[frameIndex], palette: sheet.palette).utf8))
        return ExitCode.success
    }

    private static func sheet(from outcome: SpritePackLoader.LoadOutcome, packName: String, accent: AccentColor?) -> SpriteSheet? {
        switch outcome {
        case .loaded(let pack):
            guard let inks = pack.accentInks,
                  let tint = SpriteAccentTint.tint(chosenAccent: accent, accentInks: inks)
            else { return pack.sheet }
            return SpriteAccentTint.tinted(pack.sheet, inks: inks, accent: tint)
        case .failed, .notDownloaded:
            return packName == SpritePackLoader.defaultPackName ? SpriteSheet.claude8Bit : nil
        }
    }
}
