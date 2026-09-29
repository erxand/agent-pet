import Foundation

let commandLineArguments = Array(CommandLine.arguments.dropFirst())
exit(AgentPetCommandLine.run(arguments: commandLineArguments))
