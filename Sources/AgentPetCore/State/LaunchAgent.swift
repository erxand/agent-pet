import Foundation

enum LaunchctlSubcommand: String {
    case kickstart
    case bootstrap
}

enum LaunchctlOutcome: Equatable {
    case succeeded
    case failed
    case timedOut
}

enum LaunchAgent {
    static let label = "com.agent-pet.daemon"

    private static let launchctlExecutablePath = "/bin/launchctl"
    private static let launchctlTimeoutInSeconds: TimeInterval = 5
    private static let libraryDirectoryName = "Library"
    private static let launchAgentsDirectoryName = "LaunchAgents"
    private static let propertyListFileExtension = "plist"
    private static let graphicalUserDomainPrefix = "gui/"
    private static let serviceTargetSeparator = "/"

    static var propertyListFile: URL {
        PetPaths.homeDirectory
            .appendingPathComponent(libraryDirectoryName, isDirectory: true)
            .appendingPathComponent(launchAgentsDirectoryName, isDirectory: true)
            .appendingPathComponent(label, isDirectory: false)
            .appendingPathExtension(propertyListFileExtension)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: propertyListFile.path)
    }

    static var domainTarget: String {
        graphicalUserDomainPrefix + String(getuid())
    }

    static var serviceTarget: String {
        domainTarget + serviceTargetSeparator + label
    }

    static func start(
        homeIsForeign: () -> Bool = AccountHome.isForeign,
        launchctl: (LaunchctlSubcommand, [String]) -> LaunchctlOutcome = { subcommand, arguments in
            runLaunchctl(subcommand: subcommand, arguments: arguments)
        }
    ) {
        guard !homeIsForeign() else { return }
        switch launchctl(.kickstart, [serviceTarget]) {
        case .succeeded, .timedOut:
            return
        case .failed:
            _ = launchctl(.bootstrap, [domainTarget, propertyListFile.path])
        }
    }

    @discardableResult
    private static func runLaunchctl(subcommand: LaunchctlSubcommand, arguments: [String]) -> LaunchctlOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchctlExecutablePath)
        process.arguments = [subcommand.rawValue] + arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return .failed
        }
        guard finished.wait(timeout: .now() + launchctlTimeoutInSeconds) == .success else {
            process.terminate()
            return .timedOut
        }
        return process.terminationStatus == ExitCode.success ? .succeeded : .failed
    }
}
