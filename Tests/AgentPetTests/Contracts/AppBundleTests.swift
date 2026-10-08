import Foundation
import Testing

@Suite("make-app.sh assembles AgentPet.app around the built executable")
struct AppBundleTests {
    private static let script = Sandbox.packageRoot.appendingPathComponent("scripts/app-bundle/make-app.sh", isDirectory: false)
    private static let defaultIconSet = Sandbox.packageRoot.appendingPathComponent("scripts/app-bundle/AppIcon.iconset", isDirectory: true)

    private let fileManager = FileManager.default
    private let base: URL

    init() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-pet-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    private func run(_ executable: String, _ arguments: [String]) throws -> CommandRun {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let standardOutput = output.fileHandleForReading.readDataToEndOfFile()
        let standardError = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandRun(
            exitStatus: process.terminationStatus,
            standardOutput: String(decoding: standardOutput, as: UTF8.self),
            standardError: String(decoding: standardError, as: UTF8.self)
        )
    }

    private func makeApp(into folder: String, extra: [String] = []) throws -> (CommandRun, URL) {
        let output = base.appendingPathComponent(folder, isDirectory: true)
        let result = try run(AppBundleTests.script.path, ["--executable", try Sandbox.binaryURL().path, "--output", output.path] + extra)
        return (result, output.appendingPathComponent("AgentPet.app", isDirectory: true))
    }

    private func contents(_ app: URL, _ path: String) throws -> Data {
        try Data(contentsOf: app.appendingPathComponent("Contents/\(path)", isDirectory: false))
    }

    @Test func theBundleHasTheExecutableTheIconAndAnInfoPlistThatNamesThem() throws {
        defer { try? fileManager.removeItem(at: base) }
        let (result, app) = try makeApp(into: "out", extra: ["--version", "2.3.4", "--build", "57"])
        #expect(result.exitStatus == 0, "\(result.standardError)")
        #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == app.path)

        let plist = try #require(
            try PropertyListSerialization.propertyList(from: contents(app, "Info.plist"), format: nil) as? [String: Any]
        )
        #expect(plist["CFBundleIdentifier"] as? String == "com.agent-pet")
        #expect(plist["CFBundleName"] as? String == "AgentPet")
        #expect(plist["CFBundleDisplayName"] as? String == "AgentPet")
        #expect(plist["CFBundleExecutable"] as? String == "agent-pet")
        #expect(plist["CFBundleIconFile"] as? String == "AppIcon")
        #expect(plist["CFBundlePackageType"] as? String == "APPL")
        #expect(plist["CFBundleShortVersionString"] as? String == "2.3.4")
        #expect(plist["CFBundleVersion"] as? String == "57")
        #expect(plist["LSUIElement"] as? Bool == true)
        #expect((plist["NSAppleEventsUsageDescription"] as? String)?.isEmpty == false)

        let executable = app.appendingPathComponent("Contents/MacOS/agent-pet", isDirectory: false)
        #expect(fileManager.isExecutableFile(atPath: executable.path))
        let icon = try contents(app, "Resources/AppIcon.icns")
        #expect(icon.prefix(4) == Data("icns".utf8))
        #expect(try contents(app, "PkgInfo") == Data("APPL????".utf8))

        let bundle = try #require(Bundle(url: app))
        #expect(bundle.bundleIdentifier == "com.agent-pet")
        #expect(bundle.executableURL?.resolvingSymlinksInPath() == executable.resolvingSymlinksInPath())

        let leftovers = try fileManager.contentsOfDirectory(atPath: app.deletingLastPathComponent().path)
        #expect(leftovers == ["AgentPet.app"])
    }

    @Test func theVersionComesFromTheRepositoryAndTheSignatureCoversTheWholeBundle() throws {
        defer { try? fileManager.removeItem(at: base) }
        let (result, app) = try makeApp(into: "out")
        #expect(result.exitStatus == 0, "\(result.standardError)")
        let version = try String(contentsOf: Sandbox.packageRoot.appendingPathComponent("VERSION"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: contents(app, "Info.plist"), format: nil) as? [String: Any]
        )
        #expect(plist["CFBundleShortVersionString"] as? String == version)
        #expect(plist["CFBundleVersion"] as? String == "1")

        let verify = try run("/usr/bin/codesign", ["--verify", "--strict", app.path])
        #expect(verify.exitStatus == 0, "\(verify.standardError)")
        let details = try run("/usr/bin/codesign", ["--display", "--verbose=2", app.path])
        #expect(details.standardError.contains("Identifier=com.agent-pet"))
        #expect(details.standardError.contains("Format=app bundle"))
    }

    @Test func theSameInputsGiveTheSameBundle() throws {
        defer { try? fileManager.removeItem(at: base) }
        let (first, firstApp) = try makeApp(into: "first")
        let (second, secondApp) = try makeApp(into: "second")
        #expect(first.exitStatus == 0 && second.exitStatus == 0)
        for path in ["Info.plist", "PkgInfo", "MacOS/agent-pet", "Resources/AppIcon.icns"] {
            #expect(try contents(firstApp, path) == contents(secondApp, path), "\(path)")
        }

        let (again, againApp) = try makeApp(into: "first")
        #expect(again.exitStatus == 0)
        #expect(try contents(againApp, "Resources/AppIcon.icns") == contents(firstApp, "Resources/AppIcon.icns"))
    }

    @Test func theIconSetIsAnInput() throws {
        defer { try? fileManager.removeItem(at: base) }
        let iconSet = base.appendingPathComponent("Other.iconset", isDirectory: true)
        try fileManager.createDirectory(at: iconSet, withIntermediateDirectories: true)
        let largest = "icon_512x512@2x.png"
        try fileManager.copyItem(
            at: AppBundleTests.defaultIconSet.appendingPathComponent(largest),
            to: iconSet.appendingPathComponent(largest)
        )
        let (custom, customApp) = try makeApp(into: "custom", extra: ["--icon-set", iconSet.path])
        let (standard, standardApp) = try makeApp(into: "standard")
        #expect(custom.exitStatus == 0 && standard.exitStatus == 0)
        #expect(try contents(customApp, "Resources/AppIcon.icns") != contents(standardApp, "Resources/AppIcon.icns"))
    }

    @Test func badInputLeavesNothingBehind() throws {
        defer { try? fileManager.removeItem(at: base) }
        let output = base.appendingPathComponent("out", isDirectory: true)
        let missing = try run(AppBundleTests.script.path, ["--executable", base.appendingPathComponent("nope").path, "--output", output.path])
        #expect(missing.exitStatus == 1)
        #expect(missing.standardError.contains("is not an executable file"))
        #expect(!fileManager.fileExists(atPath: output.path))

        let emptyIconSet = base.appendingPathComponent("Empty.iconset", isDirectory: true)
        try fileManager.createDirectory(at: emptyIconSet, withIntermediateDirectories: true)
        let (noIcon, app) = try makeApp(into: "out", extra: ["--icon-set", emptyIconSet.path])
        #expect(noIcon.exitStatus == 1)
        #expect(noIcon.standardError.contains("iconutil could not make an icon"))
        #expect(!fileManager.fileExists(atPath: app.path))
        #expect(try fileManager.contentsOfDirectory(atPath: output.path).isEmpty)

        let badVersion = try run(AppBundleTests.script.path, [
            "--executable", try Sandbox.binaryURL().path, "--output", output.path, "--version", "1.0-beta"
        ])
        #expect(badVersion.exitStatus == 1)
        #expect(!fileManager.fileExists(atPath: app.path))
    }
}
