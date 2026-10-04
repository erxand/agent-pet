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
        guard let sheet = sheet(forPackNamed: packName) else {
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

    private static func sheet(forPackNamed packName: String) -> SpriteSheet? {
        switch SpritePackLoader().load(packNamed: packName) {
        case .loaded(let pack):
            return pack.sheet
        case .failed:
            return packName == SpritePackLoader.defaultPackName ? SpriteSheet.claude8Bit : nil
        }
    }
}
