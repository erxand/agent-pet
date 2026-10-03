import Foundation
import Testing
@testable import agent_pet

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

@Suite("pure logic with no config file")
struct PureLogicCharacterizationTests {
    @Test func leastUsedAssignmentOnlyPicksAmongTheLeastUsedPacks() {
        let assignment = SpritePackAssignment(
            availablePackNames: ["claude", "golem", "nimbus"],
            packNamesInUse: ["claude", "golem", "golem"]
        )
        var generator = SeededGenerator(seed: 7)
        for _ in 0..<20 {
            #expect(assignment.pickLeastUsedPackName(using: &generator) == "nimbus")
        }
    }

    @Test func leastUsedAssignmentSpreadsTiesAndHandlesNoPacks() {
        let tied = SpritePackAssignment(availablePackNames: ["golem", "nimbus"], packNamesInUse: ["golem", "nimbus"])
        var generator = SeededGenerator(seed: 11)
        var picked: Set<String> = []
        for _ in 0..<50 {
            if let packName = tied.pickLeastUsedPackName(using: &generator) { picked.insert(packName) }
        }
        #expect(picked == ["golem", "nimbus"])
        #expect(SpritePackAssignment(availablePackNames: [], packNamesInUse: []).pickLeastUsedPackName() == nil)
    }

    @Test func aLegacyRecordDecodesItsSubagentIdsAtUpdatedAt() throws {
        let json = #"{"sessionId":"legacy","activeSubagentIds":["one"],"updatedAt":1000}"#
        let session = try JSONDecoder().decode(PetSession.self, from: Data(json.utf8))
        #expect(session.activeSubagents == [TrackedSubagent(id: "one", startedAt: 1000)])
        #expect(session.enabled)
        #expect(!session.visible)
        #expect(session.mood == .ready)
        #expect(session.agent == .claudeCode)
        #expect(session.transcriptScanOffset == 0)
    }

    @Test func labelResolutionOrder() {
        var session = PetSession.newlyEnrolled(sessionId: "label-session")
        let claudeSession = ClaudeSessionRecord(pid: 1, sessionId: "label-session", cwd: "/a/b/repo", name: "named", tmux: nil)
        #expect(PetLabel.resolve(session: session, claudeSession: nil) == "session")
        #expect(PetLabel.resolve(session: session, claudeSession: claudeSession) == "named")
        session.label = "labelled"
        #expect(PetLabel.resolve(session: session, claudeSession: claudeSession) == "labelled")
        session.nickname = "nick"
        #expect(PetLabel.resolve(session: session, claudeSession: claudeSession) == "nick")
        let unnamed = ClaudeSessionRecord(pid: 1, sessionId: "label-session", cwd: "/a/b/repo", name: nil, tmux: nil)
        #expect(PetLabel.resolve(session: PetSession.newlyEnrolled(sessionId: "x-session"), claudeSession: unnamed) == "repo")
    }

    @Test func tmuxClientListingPrefersAnAttachedClientThenTheMostActive() {
        let clients = TmuxClientListing.parse("/dev/a\tone\t5\n/dev/b\ttwo\t9\nbroken row\n/dev/c\tthree\tnot-a-number\n")
        #expect(clients.map { client in client.terminalDevicePath } == ["/dev/a", "/dev/b"])
        #expect(TmuxClientListing.preferredClient(in: clients, attachedTo: "one")?.terminalDevicePath == "/dev/a")
        #expect(TmuxClientListing.preferredClient(in: clients, attachedTo: "nobody")?.terminalDevicePath == "/dev/b")
    }

    @Test func tmuxTargetParsing() {
        let target = TmuxTarget(rawValue: "work:@3.%7")
        #expect(target?.windowTarget == "work:@3")
        #expect(target?.paneIdentifier == "%7")
        #expect(TmuxTarget(rawValue: "work") == nil)
        #expect(TmuxTarget(rawValue: ":@3.%7") == nil)
    }
}
