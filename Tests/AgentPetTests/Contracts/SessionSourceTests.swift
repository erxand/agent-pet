import Foundation
import Testing
@testable import AgentPetCore

@Suite("session source directories")
struct SessionSourceTests {
    private func writeSession(_ home: TemporaryDirectory, directory: String, processIdentifier: Int32, sessionId: String, name: String) throws {
        let json = #"{"pid":\#(processIdentifier),"sessionId":"\#(sessionId)","name":"\#(name)"}"#
        _ = try home.write(json, to: "\(directory)/\(processIdentifier).json")
    }

    @Test func tildeAndStarExpandAgainstHome() throws {
        let home = try TemporaryDirectory()
        _ = try home.makeDirectory(".claude/sessions")
        _ = try home.makeDirectory(".claude-reina/sessions")
        _ = try home.makeDirectory(".claude-work")
        _ = try home.write("not a directory", to: ".claude-file")
        let source = DirectorySessionSource(
            patterns: ["~/.claude/sessions", "~/.claude-*/sessions", "~/.claude/sessions"],
            homeDirectory: home.url
        )

        #expect(source.directories().map { directory in directory.path } == [
            home.url.appendingPathComponent(".claude/sessions").path,
            home.url.appendingPathComponent(".claude-reina/sessions").path,
            home.url.appendingPathComponent(".claude-work/sessions").path
        ])
    }

    @Test func aRelativePatternOrAMissingGlobParentExpandsToNothing() throws {
        let home = try TemporaryDirectory()
        #expect(SessionDirectoryPattern.expand("relative/sessions", homeDirectory: home.url).isEmpty)
        #expect(SessionDirectoryPattern.expand("~/missing-*/sessions", homeDirectory: home.url).isEmpty)
    }

    @Test func recordsMergeAcrossDirectoriesAndTheFirstDirectoryWins() throws {
        let home = try TemporaryDirectory()
        try writeSession(home, directory: ".claude/sessions", processIdentifier: 10, sessionId: "shared", name: "from-main")
        try writeSession(home, directory: ".claude-reina/sessions", processIdentifier: 11, sessionId: "shared", name: "from-reina")
        try writeSession(home, directory: ".claude-reina/sessions", processIdentifier: 12, sessionId: "reina-only", name: "reina")
        let source = DirectorySessionSource(patterns: ["~/.claude/sessions", "~/.claude-*/sessions"], homeDirectory: home.url)

        let records = source.recordsBySessionId()
        #expect(records["shared"]?.name == "from-main")
        #expect(records["reina-only"]?.pid == 12)
        #expect(DirectorySessionSource(patterns: ["~/.claude/sessions"], homeDirectory: home.url).recordsBySessionId()["reina-only"] == nil)
    }

    @Test func theSignatureChangesWhenAWatchedDirectoryChanges() throws {
        let home = try TemporaryDirectory()
        _ = try home.makeDirectory(".claude-reina/sessions")
        let source = DirectorySessionSource(patterns: ["~/.claude-*/sessions"], homeDirectory: home.url)
        let before = source.signature()
        try writeSession(home, directory: ".claude-reina/sessions", processIdentifier: 12, sessionId: "reina-only", name: "reina")
        #expect(source.signature() != before)
    }
}
