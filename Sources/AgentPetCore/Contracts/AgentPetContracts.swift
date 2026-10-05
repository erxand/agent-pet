import Foundation

package enum FocusCompletion {
    case waits
    case detaches
}

package struct AgentPetContracts {
    package let configuration: AgentPetConfiguration
    package let focuser: Focuser
    package let sessionSource: SessionSource
    package let colorSync: ColorSync
    package let spriteStrategy: SpriteStrategy
    package let grouping: PetGrouping
    package let spritePackLoader: SpritePackLoader
    package let displayChooser: DisplayChooser

    package init(configuration: AgentPetConfiguration, focusCompletion: FocusCompletion) {
        self.configuration = configuration
        switch configuration.focuser {
        case .tmuxIterm:
            focuser = TmuxItermFocuser()
        case .command(let arguments):
            focuser = CommandFocuser(arguments: arguments, waitsForCompletion: focusCompletion == .waits)
        }
        let sessionSource = DirectorySessionSource(patterns: configuration.sessionDirectoryPatterns)
        self.sessionSource = sessionSource
        switch configuration.colorSync {
        case .tmuxColor:
            colorSync = TmuxPromptBarColorSync()
        case .none:
            colorSync = DisabledColorSync()
        }
        let spritePackLoader = SpritePackLoader(extraDirectoryPaths: configuration.spriteDirectories)
        self.spritePackLoader = spritePackLoader
        spriteStrategy = LeastUsedSpriteStrategy(
            sessionSource: sessionSource,
            loader: spritePackLoader,
            reservedPackNames: configuration.reservedSprites
        )
        grouping = SharedKeyGrouping()
        switch configuration.display {
        case .focused:
            displayChooser = FocusedDisplayChooser()
        case .primary:
            displayChooser = PrimaryDisplayChooser()
        case .named(let displayName):
            displayChooser = NamedDisplayChooser(displayName: displayName)
        }
    }

    package var displayPlanner: PetDisplayPlanner {
        PetDisplayPlanner(
            grouping: grouping,
            disambiguatesLabels: configuration.disambiguatesLabels,
            settleSeconds: configuration.settleSeconds
        )
    }

    package static func loaded(focusCompletion: FocusCompletion = .waits) -> AgentPetContracts {
        AgentPetContracts(configuration: ConfigurationFile.load(), focusCompletion: focusCompletion)
    }
}
