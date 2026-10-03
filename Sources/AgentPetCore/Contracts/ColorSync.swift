import Foundation

package protocol ColorSync {
    func applyAccent(_ accent: AccentColor, to session: PetSession)
    func resetColor(of session: PetSession)
}

package struct TmuxPromptBarColorSync: ColorSync {
    private static let colorCommandName = "/color"
    private static let defaultColorName = "default"

    private let tmux: TmuxCommandRunning

    package init(tmux: TmuxCommandRunning = SystemTmux()) {
        self.tmux = tmux
    }

    package func applyAccent(_ accent: AccentColor, to session: PetSession) {
        guard let target = target(of: session) else { return }
        typeLine("\(TmuxPromptBarColorSync.colorCommandName) \(accent.rawValue)", target: target)
    }

    package func resetColor(of session: PetSession) {
        guard let target = target(of: session) else { return }
        typeLine("\(TmuxPromptBarColorSync.colorCommandName) \(TmuxPromptBarColorSync.defaultColorName)", target: target)
    }

    private func target(of session: PetSession) -> TmuxTarget? {
        switch session.agent {
        case .claudeCode:
            return session.parsedTmuxTarget
        case .pi:
            return nil
        }
    }

    private func typeLine(_ lineText: String, target: TmuxTarget) {
        tmux.run(
            subcommand: .sendKeys,
            arguments: [
                TmuxCommandRunner.targetFlag,
                target.rawValue,
                TmuxCommandRunner.literalFlag,
                lineText
            ]
        )
        tmux.run(
            subcommand: .sendKeys,
            arguments: [TmuxCommandRunner.targetFlag, target.rawValue, TmuxCommandRunner.enterKeyName]
        )
    }
}

package struct DisabledColorSync: ColorSync {
    package init() {}

    package func applyAccent(_ accent: AccentColor, to session: PetSession) {}

    package func resetColor(of session: PetSession) {}
}
